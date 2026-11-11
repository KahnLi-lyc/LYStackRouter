#if canImport(UIKit)
    import UIKit

    /// 标准 `UITabBarController` 宿主：每个 Tab 一个导航栈，目标域映射到 Tab 序号。
    @MainActor
    public final class LYTabBarHost: NSObject, LYRouterHost, LYNavigationEventSource, UINavigationControllerDelegate, UITabBarControllerDelegate {
        // MARK: - Properties

        /// 宿主管理的 TabBar。
        public let tabBarController: UITabBarController
        /// 目标域到 Tab 序号的映射。
        public let placements: [LYRoutePlacement: Int]
        /// 当前会话标识；变化后请调用 `router.sessionDidChange()`。
        public var sessionID: String?
        /// 是否允许导航。
        public var isReady = true
        /// 业务自己的导航代理，宿主会转发 `willShow` 与 `didShow`。
        public weak var forwardingDelegate: (any UINavigationControllerDelegate)?
        /// 业务自己的 Tab 代理。宿主创建或 `attach` 时，TabBar 上已有的代理会记录到这里；
        /// 宿主只实现 `didSelect`，其余 `UITabBarControllerDelegate` 可选方法转交给它。
        public weak var forwardingTabDelegate: (any UITabBarControllerDelegate)?
        /// 由路由器在 `attach` 时设置；设置时宿主会成为当前全部导航栈与 TabBar 的代理。
        ///
        /// 宿主创建后才放入 TabBar 的导航栈或才设置的 Tab 代理，会在 `attach` 时补装；之后若再更换，
        /// 请重新调用 `router.attach(host)`。
        public var onNavigationDidShow: ((UINavigationController) -> Void)? {
            didSet {
                if onNavigationDidShow != nil {
                    installTabDelegate()
                    installDelegates()
                }
            }
        }

        // MARK: - Initialization

        /// 创建宿主。TabBar 的每个子控制器都应是导航栈，宿主会成为它们的代理。
        public init(tabBarController: UITabBarController, placements: [LYRoutePlacement: Int]) {
            self.tabBarController = tabBarController
            self.placements = placements
            super.init()
            installTabDelegate()
            installDelegates()
        }

        // MARK: - Delegate Forwarding

        /// 宿主未实现的代理可选方法按所属协议转交：Tab 方法给 `forwardingTabDelegate`，导航方法给 `forwardingDelegate`。
        /// UIKit 只在主线程查询代理能力。
        override public nonisolated func responds(to selector: Selector!) -> Bool {
            if super.responds(to: selector) { return true }
            if Self.declares(UITabBarControllerDelegate.self, selector) {
                return MainActor.assumeIsolated { forwardingTabDelegate?.responds(to: selector) == true }
            }
            if Self.declares(UINavigationControllerDelegate.self, selector) {
                return MainActor.assumeIsolated { forwardingDelegate?.responds(to: selector) == true }
            }
            return false
        }

        /// 保留业务代理的动画、交互与 Tab 选择能力。UIKit 只在主线程调用。
        override public nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            if Self.declares(UITabBarControllerDelegate.self, selector) {
                return MainActor.assumeIsolated { forwardingTabDelegate }
            }
            if Self.declares(UINavigationControllerDelegate.self, selector) {
                return MainActor.assumeIsolated { forwardingDelegate }
            }
            return nil
        }

        // MARK: - LYRouterHost

        public var routerSessionID: String? {
            sessionID
        }

        public var isRouterReady: Bool {
            isReady
        }

        public var routerRootViewController: UIViewController? {
            tabBarController
        }

        public var activeNavigationController: UINavigationController? {
            tabBarController.selectedViewController as? UINavigationController
        }

        public var allNavigationControllers: [UINavigationController] {
            (tabBarController.viewControllers ?? []).compactMap { $0 as? UINavigationController }
        }

        public func navigationDomain(for placement: LYRoutePlacement) -> [UINavigationController] {
            if placement == .current { return activeNavigationController.map { [$0] } ?? [] }
            return navigation(at: placements[placement]).map { [$0] } ?? []
        }

        public func select(_ placement: LYRoutePlacement) -> UINavigationController? {
            if placement == .current { return activeNavigationController }
            guard let index = placements[placement], let navigation = navigation(at: index) else { return nil }
            tabBarController.selectedIndex = index
            return navigation
        }

        public func reveal(_ navigationController: UINavigationController) {
            guard let index = tabBarController.viewControllers?.firstIndex(where: { $0 === navigationController }) else {
                return
            }
            tabBarController.selectedIndex = index
        }

        // MARK: - UITabBarControllerDelegate

        /// 用户选择 Tab 后立即核对准备任务的来源。
        public func tabBarController(_ tabBarController: UITabBarController, didSelect viewController: UIViewController) {
            forwardingTabDelegate?.tabBarController?(tabBarController, didSelect: viewController)
            if let navigation = viewController as? UINavigationController { onNavigationDidShow?(navigation) }
        }

        // MARK: - UINavigationControllerDelegate

        public func navigationController(
            _ navigationController: UINavigationController,
            willShow viewController: UIViewController,
            animated: Bool
        ) {
            forwardingDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
        }

        public func navigationController(
            _ navigationController: UINavigationController,
            didShow viewController: UIViewController,
            animated: Bool
        ) {
            forwardingDelegate?.navigationController?(navigationController, didShow: viewController, animated: animated)
            onNavigationDidShow?(navigationController)
        }

        // MARK: - Private

        /// 成为 TabBar 的代理，并把原有业务代理记为转发对象。
        private func installTabDelegate() {
            guard tabBarController.delegate !== self else { return }
            forwardingTabDelegate = tabBarController.delegate
            tabBarController.delegate = self
        }

        /// 查询协议是否声明了该实例方法（必选或可选），用于决定转交对象。
        private nonisolated static func declares(_ proto: Protocol, _ selector: Selector) -> Bool {
            protocol_getMethodDescription(proto, selector, false, true).name != nil
                || protocol_getMethodDescription(proto, selector, true, true).name != nil
        }

        /// 成为全部导航栈的代理，才能把 UIKit 的 `didShow`（包括系统返回与侧滑）上报给路由器。
        private func installDelegates() {
            for navigation in allNavigationControllers where navigation.delegate !== self {
                navigation.delegate = self
            }
        }

        private func navigation(at index: Int?) -> UINavigationController? {
            guard let index, let controllers = tabBarController.viewControllers, controllers.indices.contains(index) else {
                return nil
            }
            return controllers[index] as? UINavigationController
        }
    }
#endif
