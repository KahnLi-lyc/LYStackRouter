#if canImport(UIKit)
    import UIKit

    /// 标准 `UITabBarController` 宿主：每个 Tab 一个导航栈，目标域映射到 Tab 序号。
    @MainActor
    public final class LYTabBarHost: NSObject, LYRouterHost, LYNavigationEventSource, UINavigationControllerDelegate {
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
        /// 由路由器在 `attach` 时设置。
        public var onNavigationDidShow: ((UINavigationController) -> Void)?

        // MARK: - Initialization

        /// 创建宿主。TabBar 的每个子控制器都应是导航栈，宿主会成为它们的代理。
        public init(tabBarController: UITabBarController, placements: [LYRoutePlacement: Int]) {
            self.tabBarController = tabBarController
            self.placements = placements
            super.init()
            for navigation in allNavigationControllers {
                navigation.delegate = self
            }
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

        private func navigation(at index: Int?) -> UINavigationController? {
            guard let index, let controllers = tabBarController.viewControllers, controllers.indices.contains(index) else {
                return nil
            }
            return controllers[index] as? UINavigationController
        }
    }
#endif
