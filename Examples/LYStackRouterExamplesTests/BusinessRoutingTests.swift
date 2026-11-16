import DemoRouteContract
import DemoUIKit
import UIKit
import XCTest
@testable import LYStackRouter
@testable import LYStackRouterExamples

/// 登录状态与跳转是示例业务策略；库只提供通用等待和显式失效。
@MainActor
final class BusinessRoutingTests: XCTestCase {
    func testBusinessHandlerRedirectsUserToLogin() throws {
        let account = DemoAccount()
        let host = LYSingleStackHost(root: UIViewController())
        let router = try makeRouter(host: host, account: account)
        defer { router.tearDown() }

        XCTAssertEqual(router.request(.wallet), .created)
        XCTAssertTrue(host.navigationController.topViewController is LoginPage)
        XCTAssertFalse(account.isSignedIn)
    }

    func testBusinessStateAloneDoesNotInvalidateOrConsumePending() async throws {
        let account = DemoAccount()
        let host = LYSingleStackHost(root: UIViewController())
        let router = try makeRouter(host: host, account: account)
        defer { router.tearDown() }
        let client = router.makeClient()
        let generation = router.generation
        let external = await router.open(.wallet, source: .deepLink)
        XCTAssertEqual(external, .deferred)
        XCTAssertNotNil(router.pending)

        account.signIn()
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertEqual(router.generation, generation)
        XCTAssertNotNil(router.pending, "业务状态变化本身不通知库，也不自动继续请求")
        let result = await client.open(.login, options: .init(animated: false))
        XCTAssertEqual(result, .created, "普通登录保留旧客户端")

        router.invalidateContext()
        XCTAssertNil(router.pending)
        let invalid = await client.open(.login)
        XCTAssertEqual(invalid, .failed(.contextChanged))
    }

    func testExternalWalletContinuesAfterBusinessExplicitlyNotifiesReady() async throws {
        let account = DemoAccount()
        let root = BusinessRootPage()
        let host = LYSingleStackHost(root: root)
        let router = try makeRouter(host: host, account: account)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host.navigationController
        window.makeKeyAndVisible()
        defer {
            router.tearDown()
            window.isHidden = true
            window.rootViewController = nil
        }
        let deadline = Date().addingTimeInterval(3)
        while !root.appeared || UIApplication.shared.applicationState != .active, Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(root.appeared)
        let result = await router.open(.wallet, source: .deepLink)
        XCTAssertEqual(result, .deferred)
        account.signIn()
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        XCTAssertNotNil(router.pending)
        XCTAssertNil(host.navigationController.presentedViewController)
        router.navigationDidStabilize()
        let readyDeadline = Date().addingTimeInterval(3)
        while host.navigationController.presentedViewController == nil, Date() < readyDeadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let wallet = host.navigationController.presentedViewController as? UINavigationController
        XCTAssertEqual((wallet?.topViewController as? DemoPage)?.pageID, "wallet")
        XCTAssertNil(router.pending)
        host.navigationController.dismiss(animated: false)
    }

    private func makeRouter(host: LYSingleStackHost, account: DemoAccount) throws -> LYStackRouter<DemoRoute> {
        var environment = LYRouteEnvironment()
        environment.provide(DemoMetrics.self, DemoMetrics())
        environment.provide(DemoAccount.self, account)
        return try LYStackRouter<DemoRoute>.build(
            host: host,
            modules: .explicit([AccountRouteModule.self]),
            environment: environment,
            allowsUnregistered: true
        )
    }
}

/// 初次上屏完成后再投递请求，避免把窗口启动事件误当作业务条件变化。
@MainActor
private final class BusinessRootPage: UIViewController {
    var appeared = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true
    }
}
