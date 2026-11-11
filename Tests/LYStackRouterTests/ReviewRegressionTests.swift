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

        // MARK: - Helpers

        private func makeRouter(host: any LYRouterHost) throws -> LYStackRouter<ReviewRoute> {
            try LYStackRouter<ReviewRoute>.build(host: host, modules: .explicit([ReviewModule.self]))
        }
    }

    // MARK: - Fixtures

    /// 审查回归使用的最小路由集合。
    enum ReviewRoute: LYRoutable {
        case page, other, ask

        enum Kind: CaseIterable {
            case page, other, ask
        }

        var kind: Kind {
            switch self {
            case .page: .page
            case .other: .other
            case .ask: .ask
            }
        }
    }

    /// `other` 位于 `me` 目标域；`ask` 先展示确认框。
    struct ReviewModule: LYRouteModule {
        static let moduleID = "review"

        init(environment: LYRouteEnvironment) throws {}

        func register(into builder: inout LYStackRouteRegistry<ReviewRoute>.Builder) {
            builder.page(.page) { _, context in context.show { UIViewController() } }
            builder.page(.other, policy: .init(placement: LYRoutePlacement("me"))) { _, context in
                context.show { UIViewController() }
            }
            builder.page(.ask) { _, context in
                context.confirm(title: nil, message: nil, confirmTitle: "OK", cancelTitle: "Cancel") { context in
                    context.show { UIViewController() }
                }
            }
        }
    }
#endif
