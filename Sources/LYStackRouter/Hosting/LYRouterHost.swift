#if canImport(UIKit)
    import UIKit

    /// 路由器的宿主：告诉路由器当前有哪些导航栈、如何切换目标域，以及何时可以导航。
    ///
    /// 库内提供 `LYSingleStackHost`（单个导航栈）与 `LYTabBarHost`（标准 TabBar）。
    /// 自定义宿主（例如分栏容器、自研 TabBar）需要在导航栈的 `didShow` 回调中调用
    /// `router.navigationDidShow(in:)`，并在会话变化时调用 `router.resetSession()`。
    @MainActor
    public protocol LYRouterHost: AnyObject {
        /// 当前会话标识，例如登录账号。nil 表示无会话。会话变化时宿主须调用 `router.resetSession()`。
        var routerSessionID: String? { get }
        /// 宿主是否允许业务导航，例如根视图已完成展示。
        var isRouterReady: Bool { get }
        /// 根控制器，用于判断是否有弹窗或根级转场。
        var routerRootViewController: UIViewController? { get }
        /// 当前活跃的导航栈，例如选中 Tab 的栈。
        var activeNavigationController: UINavigationController? { get }
        /// 宿主拥有的全部导航栈，用于跨域查找已有页面。
        var allNavigationControllers: [UINavigationController] { get }

        /// 某个目标域的导航域：主导航栈以及嵌套在其中的导航栈（例如分栏容器两侧）。`.current` 表示当前域。
        func navigationDomain(for placement: LYRoutePlacement) -> [UINavigationController]
        /// 切换到目标域，返回该域的主导航栈；不认识的域返回 nil。
        func select(_ placement: LYRoutePlacement) -> UINavigationController?
        /// 切换到某个导航栈所在的域，用于跨域回到已有页面。
        func reveal(_ navigationController: UINavigationController)
        /// 自定义展示钩子：返回非 nil 表示宿主已自行展示（例如放进分栏容器），路由器不再 push。
        func customShow(
            _ page: @autoclosure () -> UIViewController,
            identity: AnyHashable?,
            in navigationController: UINavigationController
        ) -> LYOpenResult?
        /// 页面被移出导航栈后的清理。默认通知 `LYRoutePageLifecycle`。
        func tearDown(_ page: UIViewController)
    }

    public extension LYRouterHost {
        /// 默认：当前域即活跃导航栈，其他域按 `select` 结果解释。
        func navigationDomain(for placement: LYRoutePlacement) -> [UINavigationController] {
            if placement == .current { return activeNavigationController.map { [$0] } ?? [] }
            return []
        }

        /// 默认不支持目标域切换。
        func select(_ placement: LYRoutePlacement) -> UINavigationController? {
            placement == .current ? activeNavigationController : nil
        }

        /// 默认不切换。
        func reveal(_ navigationController: UINavigationController) {}

        /// 默认不接管展示。
        func customShow(
            _ page: @autoclosure () -> UIViewController,
            identity: AnyHashable?,
            in navigationController: UINavigationController
        ) -> LYOpenResult? {
            nil
        }

        /// 默认通知页面的清理协议。
        func tearDown(_ page: UIViewController) {
            (page as? LYRoutePageLifecycle)?.routerDidRemovePage()
        }

        /// 默认全部导航栈即活跃栈。
        var allNavigationControllers: [UINavigationController] {
            activeNavigationController.map { [$0] } ?? []
        }
    }
#endif
