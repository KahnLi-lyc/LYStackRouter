import DemoMessages
import DemoRoutes
import LYStackRouter
import UIKit

/// 示例宿主：组合标准 `LYTabBarHost`，只额外实现会话状态与私信的分栏展示。
///
/// 演示自定义宿主无需重写 Tab 管理：除 `customShow` 外全部转交给 `LYTabBarHost`。
@MainActor
final class DemoHost: LYRouterHost, LYNavigationEventSource {
    // MARK: - Properties

    let tabs: LYTabBarHost
    /// 根视图展示完成后才允许导航，冷启动深链会先进入等待。
    var isReady = false
    /// 当前登录账号；变化后调用 `router.sessionDidChange()`。
    var sessionID: String?

    // MARK: - Initialization

    init(tabs: LYTabBarHost) {
        self.tabs = tabs
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
        tabs.allNavigationControllers
    }

    func navigationDomain(for placement: LYRoutePlacement) -> [UINavigationController] {
        tabs.navigationDomain(for: placement)
    }

    func select(_ placement: LYRoutePlacement) -> UINavigationController? {
        tabs.select(placement)
    }

    func reveal(_ navigationController: UINavigationController) {
        tabs.reveal(navigationController)
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

    // MARK: - LYNavigationEventSource

    var onNavigationDidShow: ((UINavigationController) -> Void)? {
        get { tabs.onNavigationDidShow }
        set { tabs.onNavigationDidShow = newValue }
    }
}
