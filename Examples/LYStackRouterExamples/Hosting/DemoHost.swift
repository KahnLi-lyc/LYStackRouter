import DemoMessagingFeature
import DemoRouteContract
import DemoUIKit
import LYStackRouter
import UIKit

/// 示例宿主：组合标准 `LYTabBarHost`，只额外实现会话状态与私信的分栏展示。
///
/// 演示自定义宿主无需重写 Tab 管理：除 `customShow` 外全部转交给 `LYTabBarHost`。
@MainActor
final class DemoHost: NSObject, LYRouterHost, LYNavigationEventSource, UINavigationControllerDelegate {
    // MARK: - Properties

    let tabs: LYTabBarHost
    /// 根视图展示完成后才允许导航，冷启动深链会先进入等待。
    var isReady = false
    /// 当前登录账号；变化后调用 `router.sessionDidChange()`。
    var sessionID: String?

    // MARK: - Initialization

    init(tabs: LYTabBarHost) {
        self.tabs = tabs
        super.init()
    }

    // MARK: - LYRouterHost

    var routerSessionID: String? {
        sessionID
    }

    var isRouterReady: Bool {
        isReady
    }

    var routerRootViewController: UIViewController? {
        tabs.routerRootViewController
    }

    var activeNavigationController: UINavigationController? {
        tabs.activeNavigationController
    }

    var allNavigationControllers: [UINavigationController] {
        tabs.allNavigationControllers + containers.map(\.detailNavigation)
    }

    func navigationDomain(for placement: LYRoutePlacement) -> [UINavigationController] {
        let primary = tabs.navigationDomain(for: placement)
        return primary + primary.compactMap { ($0.viewControllers.first as? ConversationsViewController)?.detailNavigation }
    }

    func select(_ placement: LYRoutePlacement) -> UINavigationController? {
        tabs.select(placement)
    }

    func reveal(_ navigationController: UINavigationController) {
        let owner = tabs.allNavigationControllers.first {
            ($0.viewControllers.first as? ConversationsViewController)?.detailNavigation === navigationController
        }
        tabs.reveal(owner ?? navigationController)
        if let owner, let container = owner.viewControllers.first, owner.topViewController !== container {
            let removed = Array(owner.viewControllers.dropFirst())
            owner.setViewControllers([container], animated: false)
            for page in removed where page.parent == nil {
                tearDown(page)
            }
        }
    }

    /// 消息 Tab 停在会话容器时，私信嵌入容器的详情区，不再 push。
    func customShow(
        _ page: @autoclosure () -> UIViewController,
        identity: AnyHashable?,
        in navigationController: UINavigationController
    ) -> LYOpenResult? {
        guard case .chat = identity?.base as? DemoPageIdentity,
              let container = navigationController.topViewController as? ConversationsViewController else { return nil }
        return container.showDetail(identity: identity) { page() }
    }

    /// 自定义详情容器同时接收调用方的展示选项。
    func customShow(
        _ page: @autoclosure () -> UIViewController,
        identity: AnyHashable?,
        in navigationController: UINavigationController,
        options: LYOpenOptions
    ) -> LYOpenResult? {
        guard case .chat = identity?.base as? DemoPageIdentity,
              let container = navigationController.topViewController as? ConversationsViewController else { return nil }
        return container.showDetail(identity: identity, animated: options.animated) { page() }
    }

    func navigationController(
        _ navigationController: UINavigationController,
        didShow viewController: UIViewController,
        animated: Bool
    ) {
        onNavigationDidShow?(navigationController)
    }

    private var containers: [ConversationsViewController] {
        tabs.allNavigationControllers.compactMap { $0.viewControllers.first as? ConversationsViewController }
    }

    // MARK: - LYNavigationEventSource

    var onNavigationDidShow: ((UINavigationController) -> Void)? {
        get { tabs.onNavigationDidShow }
        set {
            tabs.onNavigationDidShow = newValue
            for container in containers {
                container.detailNavigation.delegate = self
            }
        }
    }
}
