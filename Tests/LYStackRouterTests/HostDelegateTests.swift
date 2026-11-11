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

        /// 导航代理的可选方法转给 `forwardingDelegate`，Tab 代理的可选方法转给 `forwardingTabDelegate`，互不串用。
        func testTabHostForwardsOptionalMethodsByProtocol() {
            let tabs = UITabBarController()
            let host = LYTabBarHost(tabBarController: tabs, placements: [:])
            let navigationDelegate = NavigationOnlyDelegate()
            let tabDelegate = TabOnlyDelegate()
            host.forwardingDelegate = navigationDelegate
            host.forwardingTabDelegate = tabDelegate
            let animation = #selector(UINavigationControllerDelegate.navigationController(_:animationControllerFor:from:to:))
            let shouldSelect = #selector(UITabBarControllerDelegate.tabBarController(_:shouldSelect:))

            XCTAssertTrue(host.responds(to: animation))
            XCTAssertTrue(host.forwardingTarget(for: animation) as AnyObject? === navigationDelegate)
            XCTAssertTrue(host.responds(to: shouldSelect))
            XCTAssertTrue(host.forwardingTarget(for: shouldSelect) as AnyObject? === tabDelegate)
            host.forwardingTabDelegate = nil
            XCTAssertFalse(host.responds(to: shouldSelect), "Tab 方法不能转给导航代理")
        }

        /// 业务在创建宿主后改了 TabBar 代理，`attach` 时宿主重新接管并把它记为转发对象。
        func testAttachReinstallsTabDelegate() throws {
            let tabs = UITabBarController()
            tabs.viewControllers = makeStacks()
            let host = LYTabBarHost(tabBarController: tabs, placements: [:])
            let business = TabOnlyDelegate()
            tabs.delegate = business
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self]),
                environment: makeEnvironment(),
                allowsUnregistered: true
            )
            XCTAssertTrue(tabs.delegate === host)
            XCTAssertTrue(host.forwardingTabDelegate === business)
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

    /// 只实现导航动画方法的业务代理。
    @MainActor
    private final class NavigationOnlyDelegate: NSObject, UINavigationControllerDelegate {
        func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                                  from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
            nil
        }
    }

    /// 只实现 Tab 选择方法的业务代理。
    @MainActor
    private final class TabOnlyDelegate: NSObject, UITabBarControllerDelegate {
        func tabBarController(_ tabBarController: UITabBarController, shouldSelect viewController: UIViewController) -> Bool {
            true
        }
    }
#endif
