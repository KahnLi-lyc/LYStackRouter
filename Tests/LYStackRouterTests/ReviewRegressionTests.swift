#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 0.2.0 审查发现的回归：无活跃栈请求、登录后的客户端、展示阶段的宿主就绪与子控制器来源。
    @MainActor
    final class ReviewRegressionTests: XCTestCase {
        // MARK: - Active Navigation

        /// 选中 Tab 不是导航栈时，不带来源的跨 Tab 请求与 0.1.1 一致，仍可切换并展示。
        func testRequestWithoutActiveNavigationStillSwitchesPlacement() throws {
            let tabs = UITabBarController()
            tabs.viewControllers = [UIViewController(), UINavigationController(rootViewController: UIViewController())]
            tabs.selectedIndex = 0
            let host = LYTabBarHost(tabBarController: tabs, placements: [LYRoutePlacement("me"): 1])
            let router = try makeRouter(host: host)
            defer { router.tearDown() }

            XCTAssertNil(host.activeNavigationController)
            XCTAssertEqual(router.request(.other), .created)
            XCTAssertEqual(tabs.selectedIndex, 1)
        }

        // MARK: - Session

        /// 游客期间创建的页面客户端在登录（nil → A）后仍可导航。
        func testPageClientSurvivesLogin() async throws {
            let root = UIViewController()
            let host = LYSingleStackHost(root: root)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient(from: root)

            host.sessionID = "A"
            router.sessionDidChange()

            let result = await client.open(.page, options: .init(animated: false))
            XCTAssertEqual(result, .created)
        }

        /// 切换账号（A → B）后，旧会话的客户端失效。
        func testSwitchingAccountInvalidatesClient() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.sessionID = "A"
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()

            host.sessionID = "B"
            router.sessionDidChange()

            let result = await client.open(.page, options: .init(animated: false))
            XCTAssertEqual(result, .failed(.contextChanged))
            let fresh = await router.makeClient().open(.page, options: .init(animated: false))
            XCTAssertEqual(fresh, .created)
        }

        /// 退出登录（A → nil）后，旧会话的客户端失效。
        func testSignOutInvalidatesClient() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.sessionID = "A"
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()

            host.sessionID = nil
            router.sessionDidChange()

            let result = await client.open(.page, options: .init(animated: false))
            XCTAssertEqual(result, .failed(.contextChanged))
        }

        /// 原宿主已释放后再绑定新宿主，旧客户端同样失效，不能在新宿主上继续导航。
        func testReleasedHostReplacementInvalidatesClient() async throws {
            var original: LYSingleStackHost? = LYSingleStackHost(root: UIViewController())
            weak var released: LYSingleStackHost?
            released = original
            let router = try makeRouter(host: XCTUnwrap(original))
            defer { router.tearDown() }
            let client = router.makeClient()
            original = nil
            XCTAssertNil(released)

            let replacement = LYSingleStackHost(root: UIViewController())
            router.attach(replacement)
            let result = await client.open(.page, options: .init(animated: false))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(replacement.navigationController.viewControllers.count, 1)
        }

        /// 宿主会话已变为另一账号但尚未调用 `sessionDidChange()` 时，旧客户端也不能跨账号导航。
        func testClientRejectsUnreportedAccountSwitch() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.sessionID = "A"
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()

            host.sessionID = "B"
            let result = await client.open(.page, options: .init(animated: false))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        // MARK: - Host Readiness

        /// 展示阶段（确认框已交给 UIKit、展示完成回调尚未到达）宿主暂时未就绪，不应把执行结算为 contextChanged。
        func testHostNotReadyDoesNotTerminatePresentingExecution() throws {
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            router.confirmationPresenter = { _, _, _, _ in true }

            XCTAssertEqual(router.request(.ask), .awaitingConfirmation)
            XCTAssertTrue(router.isNavigating)
            host.isReady = false
            router.navigationDidStabilize()
            XCTAssertTrue(router.isNavigating, "展示中的执行不能因宿主未就绪被终止")
        }

        /// 准备阶段遇到宿主未就绪仍被终止，结果为 contextChanged。
        func testHostNotReadyStillTerminatesPreparingExecution() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeRouter(host: host)
            defer { router.tearDown() }

            let opening = Task { await router.open(.slow) }
            await waitUntil { router.isNavigating }
            host.isReady = false
            router.navigationDidStabilize()
            let result = await opening.value
            XCTAssertEqual(result, .failed(.contextChanged))
        }

        // MARK: - Origin Results

        /// 显式来源结果表：失效来源对用户忽略、对外部失败；被阻挡来源对用户忽略、对外部等待。
        func testExplicitOriginResultTable() async throws {
            let root = UIViewController()
            let host = LYSingleStackHost(root: root)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            let stale = UIViewController()
            host.navigationController.pushViewController(stale, animated: false)
            host.navigationController.popViewController(animated: false)

            XCTAssertEqual(router.request(.page, options: .init(animated: false, from: stale)), .ignored)
            let staleUser = await router.open(.page, options: .init(animated: false, from: stale))
            XCTAssertEqual(staleUser, .ignored)
            let staleExternal = await router.open(.page, source: .push, options: .init(animated: false, from: stale))
            XCTAssertEqual(staleExternal, .failed(.contextChanged))
            let staleClient = await router.makeClient(from: stale).open(.page, options: .init(animated: false))
            XCTAssertEqual(staleClient, .ignored)
            XCTAssertNil(router.pending)

            host.isReady = false
            XCTAssertEqual(router.request(.page, options: .init(animated: false, from: root)), .ignored)
            let blockedUser = await router.open(.page, options: .init(animated: false, from: root))
            XCTAssertEqual(blockedUser, .ignored)
            let blockedClient = await router.makeClient(from: root).open(.page, options: .init(animated: false))
            XCTAssertEqual(blockedClient, .ignored)
            let blockedExternal = await router.open(.page, source: .push, options: .init(animated: false, from: root))
            XCTAssertEqual(blockedExternal, .deferred)
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        /// 来源页面释放后，客户端返回忽略，不会改用当前栈顶。
        func testReleasedClientSourceIsIgnoredWithoutRetargeting() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            var client: LYRouteClient<ReviewRoute>!
            autoreleasepool {
                client = router.makeClient(from: UIViewController())
            }

            let open = await client.open(.page, options: .init(animated: false))
            let dismiss = await client.dismiss(animated: false)
            XCTAssertEqual(open, .ignored)
            XCTAssertEqual(dismiss, .ignored)
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        // MARK: - Child Origin

        /// 栈顶页面的子控制器（分页、分段）可以作为来源。
        func testChildOfTopPageIsValidOrigin() throws {
            let root = UIViewController()
            let child = embedChild(in: root)
            let host = LYSingleStackHost(root: root)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }

            XCTAssertEqual(router.request(.page, options: .init(animated: false, from: child)), .created)
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
        }

        /// 子控制器所在页面已不在栈顶时，按失效来源忽略。
        func testChildOfCoveredPageIsIgnored() throws {
            let root = UIViewController()
            let child = embedChild(in: root)
            let host = LYSingleStackHost(root: root)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            host.navigationController.pushViewController(UIViewController(), animated: false)

            XCTAssertEqual(router.request(.page, options: .init(animated: false, from: child)), .ignored)
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
        }

        /// 页面内嵌的导航栈只认最近一层：嵌套栈没有声明为宿主域时，来源按失效处理。
        func testChildInsideNestedNavigationUsesNearestStack() throws {
            let root = UIViewController()
            let inner = UIViewController()
            let nested = UINavigationController(rootViewController: inner)
            root.addChild(nested)
            root.view.addSubview(nested.view)
            nested.didMove(toParent: root)
            let host = LYSingleStackHost(root: root)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }

            XCTAssertEqual(router.request(.page, options: .init(animated: false, from: inner)), .ignored)
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
            XCTAssertEqual(nested.viewControllers.count, 1)
        }

        // MARK: - Dropped Requests

        /// 新的外部请求取代等待请求时，观察者收到 superseded。
        func testSupersededPendingNotifiesObserverOnce() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.isReady = false
            let observer = DropObserver()
            let router = try makeRouter(host: host, observers: [observer])
            defer { router.tearDown() }

            _ = await router.open(.page, source: .push)
            _ = await router.open(.other, source: .deepLink)
            XCTAssertEqual(observer.dropped.map(\.kind), [.page])
            XCTAssertEqual(observer.dropped.map(\.reason), [.superseded])
            XCTAssertEqual(observer.dropped.map(\.source), [.push])
        }

        /// 新的外部请求直接准入执行时，也取代更早的等待请求。
        func testAdmittedExternalRequestSupersedesPending() async throws {
            let tabs = UITabBarController()
            let blocked = UINavigationController(rootViewController: UIViewController())
            let current = UINavigationController(rootViewController: UIViewController())
            tabs.viewControllers = [current, blocked]
            let host = LYTabBarHost(tabBarController: tabs, placements: [LYRoutePlacement("me"): 1])
            let observer = DropObserver()
            let router = try makeRouter(host: host, observers: [observer])
            defer { router.tearDown() }
            let blocker = BlockingNavigationProbe()
            blocked.setViewControllers([blocker], animated: false)
            blocker.isBlocking = true

            let deferred = await router.open(.other, source: .push)
            XCTAssertEqual(deferred, .deferred)
            let admitted = await router.open(.page, source: .deepLink, options: .init(animated: false))
            XCTAssertEqual(admitted, .created)
            XCTAssertEqual(observer.dropped.map(\.reason), [.superseded])
            XCTAssertNil(router.pending)
        }

        /// 重置会话、停止路由器分别报告 sessionReset 与 stopped。
        func testResetAndTearDownReportDropReasons() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.isReady = false
            let observer = DropObserver()
            let router = try makeRouter(host: host, observers: [observer])

            _ = await router.open(.page, source: .push)
            router.resetSession()
            _ = await router.open(.page, source: .push)
            router.tearDown()
            router.tearDown()
            XCTAssertEqual(observer.dropped.map(\.reason), [.sessionReset, .stopped])
        }

        /// 来源失效的等待请求被丢弃，不再结算，只通知一次。
        func testPendingWithUnavailableOriginReportsDrop() async throws {
            let root = UIViewController()
            let host = LYSingleStackHost(root: root)
            host.isReady = false
            let observer = DropObserver()
            let router = try makeRouter(host: host, observers: [observer])
            defer { router.tearDown() }

            let result = await router.open(.page, source: .push, options: .init(animated: false, from: root))
            XCTAssertEqual(result, .deferred)
            host.navigationController.pushViewController(UIViewController(), animated: false)
            host.isReady = true
            router.navigationDidStabilize()
            router.navigationDidStabilize()
            for _ in 0 ..< 5 {
                await Task.yield()
            }
            XCTAssertNil(router.pending)
            XCTAssertEqual(observer.dropped.map(\.reason), [.originUnavailable])
            XCTAssertEqual(observer.settled, [.deferred])
        }

        /// 宿主会话在未通知路由器的情况下变化，执行前发现不符时报告 sessionChanged。
        func testPendingWithChangedSessionReportsDrop() async throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.sessionID = "A"
            host.isReady = false
            let observer = DropObserver()
            let router = try makeRouter(host: host, observers: [observer])
            defer { router.tearDown() }

            _ = await router.open(.page, source: .push)
            host.sessionID = "B"
            host.isReady = true
            router.navigationDidStabilize()
            await waitUntil { router.pending == nil }
            for _ in 0 ..< 5 {
                await Task.yield()
            }
            XCTAssertEqual(observer.dropped.map(\.reason), [.sessionChanged])
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        // MARK: - Presentation

        /// 系统导航控制器（以相册为例）不被 `present` 自动接管；普通导航栈与业务子类照常接管。
        /// `UIVideoEditorController` 在测试宿主中无法直接构造，规则与相册相同。
        func testSystemNavigationControllersAreExcludedFromAdoption() {
            XCTAssertTrue(LYStackRouter<ReviewRoute>.isSystemNavigation(UIImagePickerController()))
            XCTAssertFalse(LYStackRouter<ReviewRoute>.isSystemNavigation(UINavigationController()))
            XCTAssertFalse(LYStackRouter<ReviewRoute>.isSystemNavigation(BusinessNavigationController()))
        }

        // MARK: - Context

        /// `revealExisting` 切换目标栈后，上下文返回本次执行的实时目标栈。
        func testContextNavigationFollowsRevealedStack() throws {
            let first = UINavigationController(rootViewController: UIViewController())
            let second = UINavigationController(rootViewController: RevealTarget())
            let tabs = UITabBarController()
            tabs.viewControllers = [first, second]
            let host = LYTabBarHost(tabBarController: tabs, placements: [:])
            let probe = ReviewProbe()
            var environment = LYRouteEnvironment()
            environment.provide(ReviewProbe.self, probe)
            let router = try LYStackRouter<ReviewRoute>.build(host: host, modules: .explicit([ReviewModule.self]), environment: environment)
            defer { router.tearDown() }

            XCTAssertEqual(router.request(.reveal), .alreadyVisible)
            XCTAssertTrue(probe.navigation === second)
            XCTAssertEqual(tabs.selectedIndex, 1)
        }

        // MARK: - Helpers

        private func makeRouter(host: any LYRouterHost, observers: [DropObserver] = []) throws -> LYStackRouter<ReviewRoute> {
            try LYStackRouter<ReviewRoute>.build(host: host, modules: .explicit([ReviewModule.self]), observers: observers)
        }

        private func embedChild(in parent: UIViewController) -> UIViewController {
            let child = UIViewController()
            parent.addChild(child)
            parent.view.addSubview(child.view)
            child.didMove(toParent: parent)
            return child
        }

        private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
            for _ in 0 ..< 200 where !condition() {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(condition(), "等待条件超时")
        }
    }

    /// 记录等待请求丢弃与结算结果的观察者。
    @MainActor
    final class DropObserver: LYRouteObserver {
        typealias Route = ReviewRoute

        struct Drop {
            let kind: ReviewRoute.Kind
            let source: LYRouteSource
            let reason: LYPendingDropReason
        }

        private(set) var dropped: [Drop] = []
        private(set) var settled: [LYOpenResult] = []

        func routeDidSettle(_ kind: ReviewRoute.Kind?, source: LYRouteSource, result: LYOpenResult) {
            settled.append(result)
        }

        func routeDidDropPending(_ kind: ReviewRoute.Kind, source: LYRouteSource, reason: LYPendingDropReason) {
            dropped.append(Drop(kind: kind, source: source, reason: reason))
        }
    }

    /// 记录处理器读取到的上下文状态。
    @MainActor
    final class ReviewProbe {
        weak var navigation: UINavigationController?
    }

    /// 业务自定义的导航栈子类，应当照常被接管。
    final class BusinessNavigationController: UINavigationController {}

    /// `revealExisting` 查找的目标页面。
    final class RevealTarget: UIViewController {}

    /// 栈顶页面可设置为“正在展示弹窗”，用于阻挡目标域。
    final class BlockingNavigationProbe: UIViewController {
        var isBlocking = false

        override var presentedViewController: UIViewController? {
            isBlocking ? UIViewController() : super.presentedViewController
        }
    }

    // MARK: - Fixtures

    /// 审查回归使用的最小路由集合。
    enum ReviewRoute: LYRoutable {
        case page, other, ask, slow, reveal

        enum Kind: CaseIterable {
            case page, other, ask, slow, reveal
        }

        var kind: Kind {
            switch self {
            case .page: .page
            case .other: .other
            case .ask: .ask
            case .slow: .slow
            case .reveal: .reveal
            }
        }
    }

    /// `other` 位于 `me` 目标域且允许外部打开；`ask` 先展示确认框；`slow` 的准备永不返回。
    struct ReviewModule: LYRouteModule {
        static let moduleID = "review"
        let probe: ReviewProbe?

        init(environment: LYRouteEnvironment) throws {
            probe = try? environment.require(ReviewProbe.self)
        }

        func register(into builder: inout LYStackRouteRegistry<ReviewRoute>.Builder) {
            builder.page(.page, policy: .init(allowsExternal: true)) { _, context in context.show { UIViewController() } }
            builder.page(.other, policy: .init(placement: LYRoutePlacement("me"), allowsExternal: true)) { _, context in
                context.show { UIViewController() }
            }
            builder.page(.ask) { _, context in
                context.confirm(title: nil, message: nil, confirmTitle: "OK", cancelTitle: "Cancel") { context in
                    context.show { UIViewController() }
                }
            }
            let probe = probe
            builder.page(.reveal) { _, context in
                if !context.revealExisting(where: { $0 is RevealTarget }) { context.fail(.unavailable) }
                probe?.navigation = context.navigationController
            }
            builder.page(.slow) { _, context in
                context.prepare { _ in
                    await withCheckedContinuation { (_: CheckedContinuation<Void, Never>) in }
                }
            }
        }
    }
#endif
