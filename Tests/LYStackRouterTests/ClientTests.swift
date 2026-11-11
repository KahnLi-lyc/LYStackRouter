#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 可注入客户端的代次、来源与弱持有约束。
    @MainActor
    final class ClientTests: XCTestCase {
        func testWindowClientOpensTypedRouteAndURL() async throws {
            let host = makeTabHost()
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()

            let typed = await client.open(.club("one"), options: .init(animated: false))
            XCTAssertEqual(typed, .created)
            let url = try await client.openURL(XCTUnwrap(URL(string: "test://club/two")), options: .init(animated: false))
            XCTAssertEqual(url, .created)
            XCTAssertEqual((host.activeNavigationController?.topViewController as? TestPage)?.identity, .club("two"))
        }

        func testSessionResetInvalidatesExistingClient() async throws {
            let host = makeTabHost()
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()
            router.resetSession()

            let result = await client.open(.club("one"))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(host.activeNavigationController?.viewControllers.count, 1)
            let fresh = await router.makeClient().open(.club("fresh"))
            XCTAssertEqual(fresh, .created)
        }

        func testHostReplacementInvalidatesClient() async throws {
            let host = makeTabHost()
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()
            let replacement = makeTabHost()
            router.attach(replacement)

            let result = await client.open(.club("one"))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(replacement.activeNavigationController?.viewControllers.count, 1)
            withExtendedLifetime(host) {}
        }

        func testClientDoesNotRetainRouter() async throws {
            let host = makeTabHost()
            var router: LYStackRouter<AppRoute>? = try makeClientRouter(host: host)
            weak var weakRouter: LYStackRouter<AppRoute>?
            weakRouter = router
            let client = try XCTUnwrap(router).makeClient()
            router = nil

            XCTAssertNil(weakRouter)
            let result = await client.open(.club("one"))
            XCTAssertEqual(result, .failed(.contextChanged))
        }

        func testRetainedContextCreatesConsistentlyInvalidClientAfterRouterDeallocation() async throws {
            let probe = Probe()
            var environment = LYRouteEnvironment()
            environment.provide(Probe.self, probe)
            let host = LYSingleStackHost(root: UIViewController())
            var router: LYStackRouter<AppRoute>? = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([ProbeModule.self]),
                environment: environment,
                allowsUnregistered: true
            )
            XCTAssertEqual(router?.request(.club("one")), .created)
            let context = try XCTUnwrap(probe.contexts.first)
            weak var weakRouter: LYStackRouter<AppRoute>?
            weakRouter = router
            router = nil
            XCTAssertNil(weakRouter)
            let client = context.makeClient()

            let open = await client.open(.club("two"))
            let openURL = try await client.openURL(XCTUnwrap(URL(string: "test://club/two")))
            let dismiss = await client.dismiss(animated: false)
            XCTAssertEqual(open, .failed(.contextChanged))
            XCTAssertEqual(openURL, .failed(.contextChanged))
            XCTAssertEqual(dismiss, .failed(.contextChanged))
        }

        func testClientDoesNotRetainSource() async throws {
            let host = makeTabHost()
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            weak var weakPage: TestPage?
            var client: LYRouteClient<AppRoute>!
            autoreleasepool {
                let page = TestPage(.profile("source"))
                weakPage = page
                client = router.makeClient(from: page)
            }

            XCTAssertNil(weakPage)
            let result = await client.open(.club("one"))
            XCTAssertEqual(result, .failed(.contextChanged))
        }

        func testRemovedSourceCannotRetargetToCurrentTop() async throws {
            let host = makeTabHost()
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            let navigation = try XCTUnwrap(host.activeNavigationController)
            let page = TestPage(.profile("source"))
            navigation.pushViewController(page, animated: false)
            let client = router.makeClient(from: page)
            navigation.popViewController(animated: false)

            let result = await client.open(.club("one"))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertEqual(navigation.viewControllers.count, 1)
        }

        func testCoveredSourceCannotOpenOrDismissCurrentTop() async throws {
            let host = makeTabHost()
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            let navigation = try XCTUnwrap(host.activeNavigationController)
            let source = try XCTUnwrap(navigation.topViewController)
            let client = router.makeClient(from: source)
            let covering = TestPage(.profile("covering"))
            navigation.pushViewController(covering, animated: false)

            let open = await client.open(.club("one"))
            let dismiss = await client.dismiss(animated: false)
            XCTAssertEqual(open, .failed(.contextChanged))
            XCTAssertEqual(dismiss, .failed(.contextChanged))
            XCTAssertTrue(navigation.topViewController === covering)
        }

        func testDismissPopsBoundTopAndIgnoresHostRoot() async throws {
            let host = makeTabHost()
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            let navigation = try XCTUnwrap(host.activeNavigationController)
            let root = try XCTUnwrap(navigation.topViewController)
            let rootClient = router.makeClient(from: root)
            let ignored = await rootClient.dismiss(animated: false)
            XCTAssertEqual(ignored, .ignored)

            let page = TestPage(.profile("source"))
            navigation.pushViewController(page, animated: false)
            let client = router.makeClient(from: page)
            let popped = await client.dismiss(animated: false)
            XCTAssertEqual(popped, .reused)
            XCTAssertTrue(navigation.topViewController === root)
            XCTAssertEqual(page.removedCount, 1)
        }

        func testWindowClientCannotPopStackCoveredByRootPresentation() async throws {
            let root = UIViewController()
            let page = TestPage(.profile("covered"))
            let navigation = UINavigationController(rootViewController: root)
            navigation.pushViewController(page, animated: false)
            let tabs = CoveredTabBarController()
            tabs.viewControllers = [navigation]
            let host = LYTabBarHost(tabBarController: tabs, placements: [:])
            let router = try makeClientRouter(host: host)
            defer { router.tearDown() }
            let client = router.makeClient()
            tabs.coveringController = UIViewController()

            let result = await client.dismiss(animated: false)
            XCTAssertEqual(result, .ignored)
            XCTAssertTrue(navigation.topViewController === page)
            XCTAssertEqual(page.removedCount, 0)
        }

        func testClientCanBeReplacedWithSendableTestDouble() async throws {
            let probe = ClientProbe()
            let client = LYRouteClient<AppRoute>(open: { route, options in
                probe.route = route
                probe.animated = options.animated
                return .performed
            }, openURL: { url, _ in
                probe.url = url
                return .alreadyVisible
            }, dismiss: { animated in
                probe.animated = animated
                return .reused
            })
            requireSendable(client)

            let open = await client.open(.club("mock"), options: .init(animated: false))
            XCTAssertEqual(open, .performed)
            XCTAssertEqual(probe.route, .club("mock"))
            XCTAssertEqual(probe.animated, false)
            let url = try XCTUnwrap(URL(string: "test://club/mock"))
            let urlResult = await client.openURL(url)
            XCTAssertEqual(urlResult, .alreadyVisible)
            XCTAssertEqual(probe.url, url)
            let dismiss = await client.dismiss(animated: true)
            XCTAssertEqual(dismiss, .reused)
            XCTAssertEqual(probe.animated, true)
        }

        // MARK: - Helpers

        private func makeClientRouter(host: LYTabBarHost) throws -> LYStackRouter<AppRoute> {
            try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self, ChatModule.self]),
                environment: makeEnvironment(),
                url: LYURLConfiguration(schemes: ["test"])
            )
        }

        private func requireSendable(_ value: some Sendable) {}
    }

    @MainActor
    private final class CoveredTabBarController: UITabBarController {
        var coveringController: UIViewController?

        override var presentedViewController: UIViewController? {
            coveringController ?? super.presentedViewController
        }
    }

    @MainActor
    private final class ClientProbe {
        var route: AppRoute?
        var url: URL?
        var animated: Bool?
    }
#endif
