#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    @MainActor
    final class ReentrantOperationTests: XCTestCase {
        func testPageFactoryCannotPushAfterInvalidatingItsExecution() throws {
            let host = ReentrantHost()
            let router = try makeRouter(host)
            defer { router.tearDown() }
            let result = router.performUserNavigation(route: .settings, source: .user) { context in
                context.show {
                    router.invalidateContext()
                    return TestPage(.profile("stale"))
                }
            }
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(host.navigation.viewControllers.count, 1)
        }

        func testCustomShowCannotChangeSuccessorResultAfterInvalidatingExecution() throws {
            let host = ReentrantHost()
            let gate = Gate()
            let router = try makeRouter(host, gate: gate)
            defer { router.tearDown()
                gate.open() }
            host.onCustomShow = {
                host.onCustomShow = nil
                router.invalidateContext()
                _ = router.request(.slowChat("successor"))
                return .created
            }
            let result = router.request(.club("old"))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(router.currentExecution?.proposedResult, .failed(.unavailable))
            XCTAssertEqual(router.currentExecution?.phase, .preparing)
            XCTAssertEqual(host.navigation.viewControllers.count, 1)
        }

        func testRevealPredicateCannotMutateStackAfterInvalidatingExecution() throws {
            let host = ReentrantHost()
            let root = try XCTUnwrap(host.navigation.topViewController)
            let retained = TestPage(.profile("retained"))
            host.navigation.pushViewController(retained, animated: false)
            let router = try makeRouter(host)
            defer { router.tearDown() }
            var reveals = 0
            host.onReveal = { reveals += 1 }
            let result = router.performUserNavigation(route: .settings, source: .user) { context in
                _ = context.revealExisting { page in
                    router.invalidateContext()
                    return page === root
                }
            }
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(reveals, 0)
            XCTAssertTrue(host.navigation.topViewController === retained)
            XCTAssertEqual(retained.removedCount, 0)
        }

        func testHostRevealCannotChangeSuccessorAfterInvalidatingExecution() throws {
            let host = ReentrantHost()
            let gate = Gate()
            let router = try makeRouter(host, gate: gate)
            defer { router.tearDown()
                gate.open() }
            host.onReveal = {
                host.onReveal = nil
                router.invalidateContext()
                _ = router.request(.slowChat("successor"))
            }
            let result = router.performUserNavigation(route: .settings, source: .user) { context in
                _ = context.revealExisting { _ in true }
            }
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(router.currentExecution?.proposedResult, .failed(.unavailable))
            XCTAssertEqual(router.currentExecution?.phase, .preparing)
            XCTAssertEqual(host.navigation.viewControllers.count, 1)
        }

        func testHostSelectionCannotDispatchOldRouteIntoSuccessor() throws {
            let host = ReentrantHost()
            let gate = Gate()
            let router = try makeRouter(host, gate: gate)
            defer { router.tearDown()
                gate.open() }
            host.onSelect = {
                host.onSelect = nil
                router.invalidateContext()
                _ = router.request(.slowChat("successor"))
            }
            let result = router.request(.settings)
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(router.currentExecution?.proposedResult, .failed(.unavailable))
            XCTAssertEqual(router.currentExecution?.phase, .preparing)
            XCTAssertEqual(host.navigation.viewControllers.count, 1)
        }

        func testPushLifecycleCannotChangeSuccessorResult() throws {
            let host = ReentrantHost()
            host.navigation.loadViewIfNeeded()
            let gate = Gate()
            let router = try makeRouter(host, gate: gate)
            defer { router.tearDown()
                gate.open() }
            let page = InvalidatingLifecyclePage()
            var invalidated = false
            page.onAdded = {
                invalidated = true
                router.invalidateContext()
                _ = router.request(.slowChat("successor"))
            }
            let result = router.performUserNavigation(route: .settings, source: .user) { $0.show { page } }
            XCTAssertTrue(invalidated)
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(router.currentExecution?.proposedResult, .failed(.unavailable))
            XCTAssertEqual(router.currentExecution?.phase, .preparing)
        }

        func testReuseCleanupCannotChangeSuccessorResult() throws {
            let host = ReentrantHost()
            let gate = Gate()
            let router = try makeRouter(host, gate: gate)
            defer { router.tearDown()
                gate.open() }
            _ = router.request(.club("existing"))
            let page = InvalidatingLifecyclePage()
            host.navigation.pushViewController(page, animated: false)
            page.onRemoved = {
                router.invalidateContext()
                _ = router.request(.slowChat("successor"))
            }
            let result = router.request(.club("existing"))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(router.currentExecution?.proposedResult, .failed(.unavailable))
            XCTAssertEqual(router.currentExecution?.phase, .preparing)
        }

        func testReplaceStackLifecycleCannotChangeSuccessorResult() throws {
            let host = ReentrantHost()
            host.navigation.loadViewIfNeeded()
            let gate = Gate()
            let router = try makeRouter(host, gate: gate)
            defer { router.tearDown()
                gate.open() }
            let root = try XCTUnwrap(host.navigation.topViewController)
            let page = InvalidatingLifecyclePage()
            var invalidated = false
            page.onAdded = {
                invalidated = true
                router.invalidateContext()
                _ = router.request(.slowChat("successor"))
            }
            let result = router.performUserNavigation(route: .settings, source: .user) {
                $0.replaceStack([root, page], animated: false)
            }
            XCTAssertTrue(invalidated)
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(router.currentExecution?.proposedResult, .failed(.unavailable))
            XCTAssertEqual(router.currentExecution?.phase, .preparing)
        }

        func testBackAndClientDismissCleanupCannotChangeSuccessorResult() async throws {
            for clientDismiss in [false, true] {
                let host = ReentrantHost()
                let gate = Gate()
                let router = try makeRouter(host, gate: gate)
                let page = InvalidatingLifecyclePage()
                host.navigation.pushViewController(page, animated: false)
                page.onRemoved = {
                    router.invalidateContext()
                    _ = router.request(.slowChat("successor"))
                }
                if clientDismiss {
                    let result = await router.makeClient(from: page).dismiss(animated: false)
                    XCTAssertEqual(result, .failed(.contextChanged))
                } else {
                    router.navigateBack(from: page, in: host.navigation)
                }
                XCTAssertEqual(router.currentExecution?.proposedResult, .failed(.unavailable))
                XCTAssertEqual(router.currentExecution?.phase, .preparing)
                router.tearDown()
                gate.open()
            }
        }

        private func makeRouter(_ host: ReentrantHost, gate: Gate = Gate()) throws -> LYStackRouter<AppRoute> {
            try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([CommunityModule.self, ChatModule.self]),
                                              environment: makeEnvironment(gate: gate))
        }
    }

    @MainActor
    private final class InvalidatingLifecyclePage: UIViewController, LYRoutePageLifecycle {
        var onAdded: (() -> Void)?
        var onRemoved: (() -> Void)?

        override func willMove(toParent parent: UIViewController?) {
            super.willMove(toParent: parent)
            guard parent != nil else { return }
            let callback = onAdded
            onAdded = nil
            callback?()
        }

        func routerDidRemovePage() {
            let callback = onRemoved
            onRemoved = nil
            callback?()
        }
    }

    @MainActor
    private final class ReentrantHost: LYRouterHost {
        let navigation = UINavigationController(rootViewController: UIViewController())
        var onCustomShow: (() -> LYOpenResult?)?
        var onReveal: (() -> Void)?
        var onSelect: (() -> Void)?

        var isRouterReady: Bool {
            true
        }

        var routerRootViewController: UIViewController? {
            navigation
        }

        var activeNavigationController: UINavigationController? {
            navigation
        }

        var allNavigationControllers: [UINavigationController] {
            [navigation]
        }

        func select(_ placement: LYRoutePlacement) -> UINavigationController? {
            onSelect?()
            return navigation
        }

        func reveal(_ navigationController: UINavigationController) {
            onReveal?()
        }

        func customShow(_ page: @autoclosure () -> UIViewController, identity: AnyHashable?, in navigationController: UINavigationController) -> LYOpenResult? {
            onCustomShow?()
        }
    }
#endif
