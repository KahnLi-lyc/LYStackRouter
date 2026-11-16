#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    @MainActor
    final class LifecycleRegressionTests: XCTestCase {
        func testRetainedContextOpenCannotEscapeInvalidatedGeneration() throws {
            let (router, host, probe) = try makeProbeRouter()
            defer { router.tearDown() }
            XCTAssertEqual(router.request(.club("one")), .created)
            let context = try XCTUnwrap(probe.contexts.first)
            router.invalidateContext()
            XCTAssertEqual(context.open(.profile("stale")), .failed(.contextChanged))
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
        }

        func testRetainedContextBackCannotEscapeInvalidatedGeneration() throws {
            let (router, host, probe) = try makeProbeRouter()
            defer { router.tearDown() }
            XCTAssertEqual(router.request(.club("one")), .created)
            let context = try XCTUnwrap(probe.contexts.first)
            let page = try XCTUnwrap(host.navigationController.topViewController)
            router.invalidateContext()
            context.back(from: page)
            XCTAssertTrue(host.navigationController.topViewController === page)
            XCTAssertEqual((page as? TestPage)?.removedCount, 0)
        }

        func testRetainedContextCannotMintFreshClientAfterInvalidation() async throws {
            let (router, host, probe) = try makeProbeRouter()
            defer { router.tearDown() }
            XCTAssertEqual(router.request(.club("one")), .created)
            let context = try XCTUnwrap(probe.contexts.first)
            router.invalidateContext()
            let result = await context.makeClient().open(.profile("stale"))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
        }

        func testCallerCancellationReleasesPreparationBeforeWorkerReturns() async throws {
            let gate = Gate()
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeRouter(host: host, gate: gate)
            defer { router.tearDown() }
            let opening = Task { await router.makeClient().open(.slowChat("cancelled")) }
            await waitUntil { gate.waiting == 1 }
            opening.cancel()
            for _ in 0 ..< 100 {
                await Task.yield()
            }
            XCTAssertFalse(router.isNavigating, "取消必须立即释放执行权，不能等待不响应取消的准备任务")
            gate.open()
            let result = await opening.value
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        func testAlreadyCancelledOpenCannotCreatePage() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let opening = Task { await router.open(.club("cancelled"), source: .push) }
            opening.cancel()
            let result = await opening.value
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
            XCTAssertNil(router.pending)
        }

        func testReplacingReleasedHostTerminatesPresentingExecution() throws {
            var original: LYSingleStackHost? = LYSingleStackHost(root: UIViewController())
            let released = WeakReference(original)
            let router = try makeRouter(host: XCTUnwrap(original))
            defer { router.tearDown() }
            let navigation = try XCTUnwrap(original?.navigationController)
            router.confirmationPresenter = { _, _, _, _ in true }
            _ = router.performUserNavigation(route: .settings, source: .user) { context in
                context.confirm(title: nil, message: nil, confirmTitle: "OK", cancelTitle: "Cancel") { _ in }
            }
            let execution = try XCTUnwrap(router.currentExecution)
            original = nil
            XCTAssertNil(released.value)
            let replacement = LYSingleStackHost(root: UIViewController())
            router.attach(replacement)
            XCTAssertEqual(execution.result, .failed(.contextChanged))
            XCTAssertFalse(router.isNavigating)
            XCTAssertEqual(router.request(.club("fresh")), .created)
            withExtendedLifetime(navigation) {}
        }

        func testInvalidationRejectsReentrantSubmissionUntilBoundaryCompletes() throws {
            let host = LYSingleStackHost(root: UIViewController())
            let observer = ReentrantLifecycleObserver()
            let router = try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                                           environment: makeEnvironment(), observers: [observer])
            defer { router.tearDown() }
            var reentrantResult: LYOpenResult?
            observer.onInvalidation = { reentrantResult = router.request(.slowChat("successor")) }
            _ = router.request(.slowChat("original"))
            router.invalidateContext()
            XCTAssertEqual(reentrantResult, .failed(.contextChanged))
            XCTAssertFalse(router.isNavigating)
            XCTAssertEqual(router.request(.club("fresh")), .created)
        }

        func testInvalidationRetainsHostStackAndDropsPendingOnce() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let observer = RecordingObserver()
            let router = try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                                           environment: makeEnvironment(), observers: [observer])
            defer { router.tearDown() }
            _ = router.request(.club("retained"))
            let page = try XCTUnwrap(host.navigationController.topViewController as? TestPage)
            host.isReady = false
            let deferred = await router.open(.club("pending"), source: .push)
            XCTAssertEqual(deferred, .deferred)
            router.invalidateContext()
            router.invalidateContext()
            XCTAssertTrue(router.host === host)
            XCTAssertTrue(host.navigationController.topViewController === page)
            XCTAssertEqual(page.removedCount, 0)
            XCTAssertEqual(observer.dropped, [.contextInvalidated])
            XCTAssertEqual(observer.settled.map(\.1), [.created, .deferred])
            host.isReady = true
            router.navigationDidStabilize()
            for _ in 0 ..< 10 {
                await Task.yield()
            }
            XCTAssertTrue(host.navigationController.topViewController === page)
            let fresh = await router.makeClient(from: page).open(.club("fresh"))
            XCTAssertEqual(fresh, .created)
        }

        func testEveryOldClientOperationRemainsInvalidAcrossRepeatedInvalidations() async throws {
            let (router, host, probe) = try makeProbeRouter()
            defer { router.tearDown() }
            _ = router.request(.club("one"))
            let context = try XCTUnwrap(probe.contexts.first)
            let oldClient = context.makeClient()
            router.invalidateContext()
            router.invalidateContext()
            for client in [oldClient, context.makeClient()] {
                let opened = await client.open(.profile("stale"))
                let url = try await client.openURL(XCTUnwrap(URL(string: "unknown://ignored")))
                let dismissed = await client.dismiss(animated: false)
                XCTAssertEqual(opened, .failed(.contextChanged))
                XCTAssertEqual(url, .failed(.contextChanged))
                XCTAssertEqual(dismissed, .failed(.contextChanged))
            }
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
        }

        func testSameHostAttachPreservesPreparationGenerationAndClient() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let gate = Gate()
            let router = try makeRouter(host: host, gate: gate)
            defer { router.tearDown() }
            let client = router.makeClient()
            let opening = Task { await router.open(.slowChat("same")) }
            await waitUntil { gate.waiting == 1 }
            let generation = router.generation
            let execution = router.currentExecution
            router.attach(host)
            XCTAssertEqual(router.generation, generation)
            XCTAssertTrue(router.currentExecution === execution)
            gate.open()
            let result = await opening.value
            XCTAssertEqual(result, .created)
            let next = await client.open(.club("next"))
            XCTAssertEqual(next, .created)
        }

        func testReplacementKeepsLatestRetryablePendingAndCleansOldBridges() async throws {
            let original = LYSingleStackHost(root: UIViewController())
            original.isReady = false
            let router = try makeRouter(host: original)
            defer { router.tearDown() }
            let modal = UINavigationController(rootViewController: UIViewController())
            let bridge = NavigationEventBridge(navigation: modal) { _ in }
            router.managedNavigations[ObjectIdentifier(modal)] = bridge
            _ = await router.open(.club("old"), source: .push)
            _ = await router.open(.club("latest"), source: .push)
            let replacement = LYSingleStackHost(root: UIViewController())
            router.attach(replacement)
            await waitUntil { router.pending == nil }
            XCTAssertTrue(router.managedNavigations.isEmpty)
            XCTAssertNil(modal.delegate)
            XCTAssertNil(original.onNavigationDidShow)
            XCTAssertEqual((replacement.navigationController.topViewController as? TestPage)?.identity, .club("latest"))
            withExtendedLifetime(bridge) {}
        }

        func testCancelledNavigationObserverCannotCancelOwner() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let gate = Gate()
            let router = try makeRouter(host: host, gate: gate)
            defer { router.tearDown() }
            let owner = Task { await router.open(.slowChat("owner")) }
            await waitUntil { gate.waiting == 1 }
            let observer = Task { await router.waitForNavigation() }
            for _ in 0 ..< 10 {
                await Task.yield()
            }
            observer.cancel()
            for _ in 0 ..< 10 {
                await Task.yield()
            }
            XCTAssertTrue(router.isNavigating)
            gate.open()
            let owned = await owner.value
            let observed = await observer.value
            XCTAssertEqual(owned, .created)
            XCTAssertEqual(observed, .created)
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
        }

        func testCancelledPresentingCallerReceivesActualUIKitResult() async throws {
            let (router, host, _) = try makeProbeRouter()
            defer { router.tearDown() }
            var onPresented: (@MainActor () -> Void)?
            router.confirmationPresenter = { _, _, _, completion in onPresented = completion
                return true }
            let opening = Task { await router.open(.room("confirmation")) }
            await waitUntil { onPresented != nil }
            opening.cancel()
            for _ in 0 ..< 10 {
                await Task.yield()
            }
            XCTAssertTrue(router.isNavigating)
            try XCTUnwrap(onPresented)()
            let result = await opening.value
            XCTAssertEqual(result, .awaitingConfirmation)
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        func testLateCancellationCannotCancelSuccessor() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let gate = Gate()
            let router = try makeRouter(host: host, gate: gate)
            defer { router.tearDown() }
            _ = router.request(.club("source"))
            let old = Task { await router.open(.slowChat("old")) }
            await waitUntil { gate.waiting == 1 }
            let source = try XCTUnwrap(host.navigationController.topViewController)
            // cancel 回调尚未回到 MainActor，返回先结束旧执行并同步准入下一次导航。
            old.cancel()
            router.navigateBack(from: source, in: host.navigationController)
            let next = router.request(.slowChat("successor"))
            XCTAssertEqual(next, .failed(.unavailable))
            await waitUntil { gate.waiting == 2 }
            XCTAssertTrue(router.isNavigating)
            let successor = try XCTUnwrap(router.currentExecution)
            gate.open()
            let oldResult = await old.value
            let successorResult = await successor.value()
            XCTAssertEqual(oldResult, .failed(.contextChanged))
            XCTAssertEqual(successorResult, .created)
            XCTAssertEqual((host.navigationController.topViewController as? TestPage)?.identity, .chat("successor"))
        }

        func testAlreadyCancelledURLCannotParseOrReplacePending() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.isReady = false
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            _ = await router.open(.club("retained"), source: .push)
            let sequence = router.pending?.sequence
            let routeOpening = Task { await router.open(.club("cancelled"), source: .push) }
            routeOpening.cancel()
            let routeResult = await routeOpening.value
            XCTAssertEqual(routeResult, .failed(.contextChanged))
            XCTAssertEqual(router.pending?.sequence, sequence)
            XCTAssertEqual(router.pending?.route, .club("retained"))
            for url in try [XCTUnwrap(URL(string: "test://club/cancelled")), XCTUnwrap(URL(string: "wrong://unknown"))] {
                let opening = Task { await router.openURL(url) }
                opening.cancel()
                let result = await opening.value
                XCTAssertEqual(result, .failed(.contextChanged))
                XCTAssertEqual(router.pending?.sequence, sequence)
                XCTAssertEqual(router.pending?.route, .club("retained"))
            }
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        func testCancellationAfterDeferredResultDoesNotWithdrawIndependentPending() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.isReady = false
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let opening = Task { await router.open(.club("deferred"), source: .push) }
            let result = await opening.value
            XCTAssertEqual(result, .deferred)
            opening.cancel()
            host.isReady = true
            router.navigationDidStabilize()
            await waitUntil { router.pending == nil }
            XCTAssertEqual((host.navigationController.topViewController as? TestPage)?.identity, .club("deferred"))
        }

        func testInvalidatedPreparationDoesNotStartWorkerAfterBoundary() async throws {
            let (router, host, probe) = try makeProbeRouter()
            defer { router.tearDown() }
            _ = router.request(.slowChat("never-start"))
            router.invalidateContext()
            for _ in 0 ..< 20 {
                await Task.yield()
            }
            XCTAssertEqual(probe.gate.waiting, 0)
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
            probe.gate.open()
        }

        func testStoppingDuringInvalidationKeepsStoppedResultPrecedence() throws {
            let host = LYSingleStackHost(root: UIViewController())
            let observer = ReentrantLifecycleObserver()
            let gate = Gate()
            let router = try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                                           environment: makeEnvironment(gate: gate), observers: [observer])
            defer { gate.open() }
            let modal = UINavigationController(rootViewController: UIViewController())
            let bridge = NavigationEventBridge(navigation: modal) { _ in }
            router.managedNavigations[ObjectIdentifier(modal)] = bridge
            var stoppedResult: LYOpenResult?
            observer.onInvalidation = {
                router.tearDown()
                stoppedResult = router.request(.club("stopped"))
            }
            _ = router.request(.slowChat("original"))
            router.invalidateContext()
            XCTAssertEqual(stoppedResult, .failed(.stopped))
            XCTAssertNil(router.host)
            XCTAssertFalse(router.isNavigating)
            XCTAssertTrue(router.managedNavigations.isEmpty)
            XCTAssertNil(modal.delegate)
            withExtendedLifetime(bridge) {}
        }

        func testCancellationDuringPreparationAcrossAllAsyncOpenEntrypoints() async throws {
            for entry in 0 ..< 4 {
                let gate = Gate()
                let host = LYSingleStackHost(root: UIViewController())
                let observer = RecordingObserver()
                let router = try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                                               environment: makeEnvironment(gate: gate), observers: [observer],
                                                               url: .init(schemes: ["test"]))
                let client = router.makeClient()
                let url = try XCTUnwrap(URL(string: "test://slow/cancelled"))
                let opening = Task {
                    switch entry {
                    case 0: await router.open(.slowChat("cancelled"))
                    case 1: await router.openURL(url)
                    case 2: await client.open(.slowChat("cancelled"))
                    default: await client.openURL(url)
                    }
                }
                await waitUntil { gate.waiting == 1 }
                opening.cancel()
                await waitUntil { !router.isNavigating }
                XCTAssertEqual(observer.settled.map(\.1), [.failed(.contextChanged)])
                gate.open()
                let result = await opening.value
                for _ in 0 ..< 10 {
                    await Task.yield()
                }
                XCTAssertEqual(result, .failed(.contextChanged))
                XCTAssertEqual(host.navigationController.viewControllers.count, 1)
                XCTAssertEqual(observer.settled.count, 1)
                router.tearDown()
            }
        }

        func testAlreadyCancelledClientsDoNotCreatePages() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()
            let url = try XCTUnwrap(URL(string: "test://club/cancelled"))
            let routeOpening = Task { await client.open(.club("cancelled")) }
            let urlOpening = Task { await client.openURL(url) }
            routeOpening.cancel()
            urlOpening.cancel()
            let routeResult = await routeOpening.value
            let urlResult = await urlOpening.value
            XCTAssertEqual(routeResult, .failed(.contextChanged))
            XCTAssertEqual(urlResult, .failed(.contextChanged))
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
            XCTAssertNil(router.pending)
        }

        func testStoppingDuringHostReplacementDoesNotAttachReplacement() throws {
            let host = LYSingleStackHost(root: UIViewController())
            let replacement = LYSingleStackHost(root: UIViewController())
            let observer = ReentrantLifecycleObserver()
            let gate = Gate()
            let router = try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                                           environment: makeEnvironment(gate: gate), observers: [observer])
            defer { router.tearDown()
                gate.open() }
            observer.onInvalidation = { router.tearDown() }
            _ = router.request(.slowChat("original"))
            router.attach(replacement)
            XCTAssertTrue(router.stopped)
            XCTAssertNil(router.host)
            XCTAssertNil(replacement.onNavigationDidShow)
            XCTAssertEqual(router.request(.club("stopped")), .failed(.stopped))
        }

        func testBackDuringInvalidationCannotMutateStackOrCreateExecution() throws {
            let host = LYSingleStackHost(root: UIViewController())
            let observer = ReentrantLifecycleObserver()
            let gate = Gate()
            let router = try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                                           environment: makeEnvironment(gate: gate), observers: [observer])
            defer { router.tearDown()
                gate.open() }
            _ = router.request(.club("retained"))
            let page = try XCTUnwrap(host.navigationController.topViewController as? TestPage)
            observer.onInvalidation = { router.navigateBack(from: page, in: host.navigationController) }
            _ = router.request(.slowChat("invalidated"))
            router.invalidateContext()
            XCTAssertTrue(host.navigationController.topViewController === page)
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
            XCTAssertEqual(page.removedCount, 0)
            XCTAssertNil(router.currentExecution)
        }

        private func makeProbeRouter() throws -> (LYStackRouter<AppRoute>, LYSingleStackHost, Probe) {
            let host = LYSingleStackHost(root: UIViewController())
            let probe = Probe()
            var environment = LYRouteEnvironment()
            environment.provide(Probe.self, probe)
            let router = try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([ProbeModule.self]),
                                                           environment: environment, allowsUnregistered: true)
            return (router, host, probe)
        }

        private func makeRouter(host: LYSingleStackHost, gate: Gate = Gate()) throws -> LYStackRouter<AppRoute> {
            try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                              environment: makeEnvironment(gate: gate), url: .init(schemes: ["test"]))
        }

        private func waitUntil(_ condition: @MainActor () -> Bool) async {
            for _ in 0 ..< 1000 where !condition() {
                await Task.yield()
            }
            XCTAssertTrue(condition())
        }
    }

    @MainActor
    private final class ReentrantLifecycleObserver: LYRouteObserver {
        typealias Route = AppRoute
        var onInvalidation: (() -> Void)?

        func routeDidSettle(_ kind: AppRoute.Kind?, source: LYRouteSource, result: LYOpenResult) {
            guard result == .failed(.contextChanged) else { return }
            let callback = onInvalidation
            onInvalidation = nil
            callback?()
        }
    }
#endif
