#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 内置宿主在路由器接管时为全部导航栈安装代理，与“先建宿主还是先放导航栈”的顺序无关。
    @MainActor
    final class HostDelegateTests: XCTestCase {
        func testTabsAssignedAfterHostCreationGetDelegateOnAttach() throws {
            let tabs = UITabBarController()
            let host = LYTabBarHost(tabBarController: tabs, placements: [:])
            tabs.viewControllers = makeStacks()
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self]),
                environment: makeEnvironment(),
                allowsUnregistered: true
            )
            for navigation in host.allNavigationControllers {
                XCTAssertTrue(navigation.delegate === host, "attach 后导航栈的代理应为宿主")
            }
            withExtendedLifetime(router) {}
        }

        func testTabsAssignedBeforeHostCreationKeepDelegate() throws {
            let tabs = UITabBarController()
            tabs.viewControllers = makeStacks()
            let host = LYTabBarHost(tabBarController: tabs, placements: [:])
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self]),
                environment: makeEnvironment(),
                allowsUnregistered: true
            )
            for navigation in host.allNavigationControllers {
                XCTAssertTrue(navigation.delegate === host)
            }
            withExtendedLifetime(router) {}
        }

        func testSingleStackDelegateIsRestoredOnAttach() throws {
            let host = LYSingleStackHost(root: UIViewController())
            host.navigationController.delegate = nil
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self]),
                environment: makeEnvironment(),
                allowsUnregistered: true
            )
            XCTAssertTrue(host.navigationController.delegate === host)
            withExtendedLifetime(router) {}
        }

        private func makeStacks() -> [UINavigationController] {
            (0 ..< 3).map { _ in UINavigationController(rootViewController: TestPage(nil)) }
        }
    }
#endif
