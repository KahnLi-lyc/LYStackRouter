#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    @MainActor
    final class EngineTests: XCTestCase {
        private var gate: Gate!
        private var host: LYTabBarHost!
        private var router: LYStackRouter<AppRoute>!

        override func setUp() async throws {
            gate = Gate()
            host = makeTabHost()
            router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self, ChatModule.self]),
                environment: makeEnvironment(gate: gate),
                interceptors: [.session(isActive: { [weak self] in self?.signedIn ?? false })],
                url: LYURLConfiguration(schemes: ["app"])
            )
        }

        override func tearDown() async throws {
            gate.open()
            router.tearDown()
        }

        private var signedIn = false

        private var home: UINavigationController {
            host.allNavigationControllers[0]
        }

        private func pages(_ navigation: UINavigationController) -> [PageIdentity?] {
            navigation.viewControllers.map { ($0 as? TestPage)?.identity }
        }

        // MARK: - Reuse

        func testLoopReturnsToOriginalInstanceAndKeepsStackBounded() {
            XCTAssertEqual(router.request(.club("x")), .created)
            let original = home.topViewController
            for _ in 0 ..< 5 {
                XCTAssertEqual(router.request(.profile("a")), .created)
                XCTAssertEqual(router.request(.club("y")), .created)
                XCTAssertEqual(router.request(.club("x")), .reused)
                XCTAssertTrue(home.topViewController === original)
                XCTAssertEqual(home.viewControllers.count, 2)
            }
        }

        func testRemovedPagesAreCleanedOnceAndTargetSurvives() throws {
            router.request(.club("x"))
            let target = try XCTUnwrap(home.topViewController as? TestPage)
            router.request(.profile("a"))
            let middle = try XCTUnwrap(home.topViewController as? TestPage)
            router.request(.club("y"))
            let top = try XCTUnwrap(home.topViewController as? TestPage)
            XCTAssertEqual(router.request(.club("x")), .reused)
            XCTAssertEqual(middle.removedCount, 1)
            XCTAssertEqual(top.removedCount, 1)
            XCTAssertEqual(target.removedCount, 0)
        }

        func testDifferentIdentityCreatesAndTopMatchIsAlreadyVisible() {
            XCTAssertEqual(router.request(.club("x")), .created)
            XCTAssertEqual(router.request(.club("y")), .created)
            XCTAssertEqual(router.request(.club("y")), .alreadyVisible)
            XCTAssertEqual(pages(home), [nil, .club("x"), .club("y")])
        }

        func testIdentityIsReadLiveFromThePage() throws {
            router.request(.profile("draft"))
            let page = try XCTUnwrap(home.topViewController as? TestPage)
            page.identity = .club("created")
            router.request(.profile("b"))
            XCTAssertEqual(router.request(.club("created")), .reused)
            XCTAssertTrue(home.topViewController === page)
        }

        // MARK: - Placement

        func testPlacementSelectsTargetTab() {
            XCTAssertEqual(router.request(.chat("s1")), .created)
            XCTAssertEqual(host.tabBarController.selectedIndex, 1)
            XCTAssertEqual(pages(host.allNavigationControllers[1]), [nil, .chat("s1")])
            XCTAssertEqual(router.request(.settings), .created)
            XCTAssertEqual(host.tabBarController.selectedIndex, 2)
        }

        func testRevealExistingFindsPageInAnotherTab() {
            router.request(.room("r1"))
            let room = home.topViewController
            router.request(.chat("s1"))
            XCTAssertEqual(host.tabBarController.selectedIndex, 1)
            XCTAssertEqual(router.request(.room("r1")), .alreadyVisible)
            XCTAssertEqual(host.tabBarController.selectedIndex, 0)
            XCTAssertTrue(home.topViewController === room)
        }

        // MARK: - Admission

        func testValidationAndExternalWhitelistFailBeforeSideEffects() async {
            XCTAssertEqual(router.request(.club("")), .failed(.invalidParameter))
            let external = await router.open(.profile("a"), source: .push)
            XCTAssertEqual(external, .failed(.notExternal))
            XCTAssertEqual(home.viewControllers.count, 1)
        }

        func testActionRouteReportsPerformedAndRequiresSession() {
            XCTAssertEqual(router.request(.wallet), .ignored, "未登录时用户请求被忽略")
            signedIn = true
            XCTAssertEqual(router.request(.wallet), .performed)
            XCTAssertEqual(home.viewControllers.count, 1)
        }

        func testUserRequestDuringPreparationIsIgnored() async {
            let first = Task { await router.open(.slowChat("s1")) }
            await waitUntil { self.gate.waiting == 1 }
            XCTAssertEqual(router.request(.club("x")), .ignored)
            gate.open()
            let result = await first.value
            XCTAssertEqual(result, .created)
            XCTAssertEqual(pages(home), [nil, .chat("s1")])
        }

        // MARK: - Preemption

        func testBackPreemptsPreparationAndLatePreparationCannotShow() async throws {
            router.request(.club("x"))
            let source = try XCTUnwrap(home.topViewController)
            let opening = Task { await router.open(.slowChat("s1")) }
            await waitUntil { self.gate.waiting == 1 }
            router.navigateBack(from: source, in: home)
            let result = await opening.value
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(home.viewControllers.count, 1)
            gate.open()
            await Task.yield()
            XCTAssertEqual(home.viewControllers.count, 1, "抢占后迟到的准备不能再展示页面")
            XCTAssertFalse(router.isNavigating)
        }

        func testPreparationWhoseSourceLeftIsDropped() async {
            router.request(.club("x"))
            let opening = Task { await router.open(.slowChat("s1")) }
            await waitUntil { self.gate.waiting == 1 }
            home.setViewControllers([home.viewControllers[0]], animated: false)
            gate.open()
            let result = await opening.value
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(home.viewControllers.count, 1)
        }

        // MARK: - External Requests

        func testOnlyLatestExternalRequestRunsWhenHostBecomesReady() async {
            host.isReady = false
            let a = await router.open(.club("a"), source: .push)
            let b = await router.open(.club("b"), source: .deepLink)
            let c = await router.open(.club("c"), source: .web)
            XCTAssertEqual([a, b, c], [.deferred, .deferred, .deferred])
            XCTAssertEqual(router.request(.club("user")), .ignored, "用户请求受阻时不排队")
            host.isReady = true
            router.navigationDidStabilize()
            await waitUntil { self.home.viewControllers.count == 2 }
            XCTAssertEqual(pages(home), [nil, .club("c")])
        }

        func testExternalRequestDeferredBySessionRunsAfterSignIn() async {
            let deferred = await router.open(.wallet, source: .push)
            XCTAssertEqual(deferred, .deferred)
            signedIn = true
            host.sessionID = "u1"
            router.sessionDidChange()
            await waitUntil { !self.router.isNavigating && self.router.pending == nil }
            XCTAssertNil(router.pending, "登录后等待请求被执行")
        }

        func testSwitchingAccountDropsWaitingRequest() async {
            host.sessionID = "a"
            router.sessionDidChange()
            host.isReady = false
            _ = await router.open(.club("x"), source: .push)
            XCTAssertNotNil(router.pending)
            host.sessionID = "b"
            router.sessionDidChange()
            XCTAssertNil(router.pending)
            host.isReady = true
            router.navigationDidStabilize()
            await Task.yield()
            XCTAssertEqual(home.viewControllers.count, 1)
        }

        func testSessionResetDropsWaitingRequest() async {
            host.isReady = false
            _ = await router.open(.club("a"), source: .push)
            router.resetSession()
            host.isReady = true
            router.navigationDidStabilize()
            await Task.yield()
            await Task.yield()
            XCTAssertEqual(home.viewControllers.count, 1)
        }

        func testOpenURLUsesModuleTemplatesAndRejectsUnknown() async throws {
            let url = try XCTUnwrap(URL(string: "app://nothing/here"))
            let unmatched = await router.openURL(url)
            XCTAssertEqual(unmatched, .failed(.unmatchedURL))

            let club = try XCTUnwrap(router.url(for: .club("42")))
            XCTAssertEqual(club.absoluteString, "app://club/42")
            let opened = await router.openURL(club)
            XCTAssertEqual(opened, .created)
            XCTAssertEqual(pages(home), [nil, .club("42")])

            // URL 能解析，但目标路由没有放开外部来源。
            let profile = try XCTUnwrap(URL(string: "app://profile/a"))
            let blocked = await router.openURL(profile)
            XCTAssertEqual(blocked, .failed(.notExternal))
            XCTAssertEqual(home.viewControllers.count, 2)
        }

        // MARK: - Host Lifecycle

        func testOldHostLateDetachDoesNotAffectReplacement() throws {
            let old = try XCTUnwrap(host)
            let replacement = makeTabHost()
            router.attach(replacement)
            router.detach(old)
            XCTAssertEqual(router.request(.club("x")), .created)
            XCTAssertEqual(replacement.allNavigationControllers[0].viewControllers.count, 2)
            XCTAssertEqual(old.allNavigationControllers[0].viewControllers.count, 1)
        }

        func testTearDownStopsFurtherRequests() {
            router.tearDown()
            router.tearDown()
            XCTAssertEqual(router.request(.club("x")), .failed(.stopped))
        }

        // MARK: - Confirmation

        func testRejectedConfirmationReleasesExecution() throws {
            var late: (@MainActor () -> Void)?
            router.confirmationPresenter = { _, _, _, onPresented in
                late = onPresented
                return false
            }
            var confirmContext: LYRouteContext<AppRoute>?
            let execution = router.performUserNavigation(route: .settings, source: .user) { context in
                confirmContext = context
                context.confirm(title: "t", message: nil, confirmTitle: "ok", cancelTitle: "cancel") { _ in }
            }
            XCTAssertNotNil(confirmContext)
            XCTAssertEqual(execution, .failed(.blocked))
            XCTAssertFalse(router.isNavigating)
            XCTAssertEqual(router.request(.club("x")), .created)
            try XCTUnwrap(late)()
            XCTAssertFalse(router.isNavigating)
        }

        func testPresentedConfirmationSettlesAwaiting() {
            var presented: (@MainActor () -> Void)?
            router.confirmationPresenter = { _, _, _, onPresented in
                presented = onPresented
                return true
            }
            let result = router.performUserNavigation(route: .settings, source: .user) { context in
                context.confirm(title: "t", message: nil, confirmTitle: "ok", cancelTitle: "cancel") { _ in }
            }
            XCTAssertEqual(result, .awaitingConfirmation)
            XCTAssertTrue(router.isNavigating)
            presented?()
            XCTAssertFalse(router.isNavigating)
        }

        // MARK: - Helpers

        private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 2) async {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(condition(), "等待条件超时")
        }
    }
#endif
