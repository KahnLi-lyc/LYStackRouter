#if canImport(UIKit)
    import UIKit

    /// 单个导航栈的宿主，适合模块 Demo、测试与没有 Tab 的 App。
    @MainActor
    public final class LYSingleStackHost: NSObject, LYRouterHost, LYNavigationEventSource, UINavigationControllerDelegate {
        // MARK: - Properties

        /// 宿主拥有的导航栈。
        public let navigationController: UINavigationController
        /// 当前会话标识；变化后请调用 `router.sessionDidChange()`。
        public var sessionID: String?
        /// 是否允许导航。
        public var isReady = true
        /// 业务自己的导航代理，宿主会转发 `willShow` 与 `didShow`。
        public weak var forwardingDelegate: (any UINavigationControllerDelegate)?
        /// 由路由器在 `attach` 时设置。
        public var onNavigationDidShow: ((UINavigationController) -> Void)?

        // MARK: - Initialization

        /// 用根页面创建导航栈。
        public convenience init(root: UIViewController) {
            self.init(navigationController: UINavigationController(rootViewController: root))
        }

        /// 使用已有的导航栈，宿主会成为它的代理。
        public init(navigationController: UINavigationController) {
            self.navigationController = navigationController
            super.init()
            navigationController.delegate = self
        }

        // MARK: - LYRouterHost

        public var routerSessionID: String? {
            sessionID
        }

        public var isRouterReady: Bool {
            isReady
        }

        public var routerRootViewController: UIViewController? {
            navigationController
        }

        public var activeNavigationController: UINavigationController? {
            navigationController
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
    }
#endif
