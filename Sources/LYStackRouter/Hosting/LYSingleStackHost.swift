#if canImport(UIKit)
    import UIKit

    /// 单个导航栈的宿主，适合模块 Demo、测试与没有 Tab 的 App。
    @MainActor
    public final class LYSingleStackHost: NSObject, LYRouterHost, LYNavigationEventSource, UINavigationControllerDelegate {
        // MARK: - Properties

        /// 宿主拥有的导航栈。
        public let navigationController: UINavigationController
        /// 是否允许导航。
        public var isReady = true
        /// 业务自己的导航代理，宿主转发导航事件及动画、交互方法。业务负责持有代理。
        /// 显式设置或清空立即更新 UIKit 能力；弱代理释放后在下一次 MainActor 执行中恢复默认能力。
        public weak var forwardingDelegate: (any UINavigationControllerDelegate)? {
            didSet {
                delegateLifetime?.stop()
                delegateLifetime = forwardingDelegate.map { delegate in
                    NavigationDelegateLifetime(delegate: delegate) { [weak self] in
                        guard let self, forwardingDelegate == nil else { return }
                        refreshDelegateCapabilities()
                    }
                }
                refreshDelegateCapabilities()
            }
        }

        private var delegateLifetime: NavigationDelegateLifetime?
        /// 由路由器在 `attach` 时设置；设置时宿主会重新成为导航栈的代理。
        public var onNavigationDidShow: ((UINavigationController) -> Void)? {
            didSet {
                if onNavigationDidShow != nil, navigationController.delegate !== self { navigationController.delegate = self }
            }
        }

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

        /// 即使有安全的 nil 回退实现，也只在业务真正提供转场时声明自定义能力，保留系统侧滑。
        override public nonisolated func responds(to selector: Selector!) -> Bool {
            if selector == #selector(UINavigationControllerDelegate.navigationController(_:animationControllerFor:from:to:))
                || selector == #selector(UINavigationControllerDelegate.navigationController(_:interactionControllerFor:)) {
                return MainActor.assumeIsolated { forwardingDelegate?.responds(to: selector) == true }
            }
            return super.responds(to: selector)
        }

        // MARK: - LYRouterHost

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

        /// 转交业务动画；无业务代理时返回 nil，使用 UIKit 默认转场。
        public func navigationController(
            _ navigationController: UINavigationController,
            animationControllerFor operation: UINavigationController.Operation,
            from fromVC: UIViewController,
            to toVC: UIViewController
        ) -> (any UIViewControllerAnimatedTransitioning)? {
            forwardingDelegate?.navigationController?(navigationController, animationControllerFor: operation, from: fromVC, to: toVC)
        }

        /// 转交业务交互；显式实现保证 UIKit 缓存的能力不依赖弱代理是否仍存活。
        public func navigationController(
            _ navigationController: UINavigationController,
            interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning
        ) -> (any UIViewControllerInteractiveTransitioning)? {
            forwardingDelegate?.navigationController?(navigationController, interactionControllerFor: animationController)
        }

        private func refreshDelegateCapabilities() {
            guard navigationController.delegate === self else { return }
            navigationController.delegate = nil
            navigationController.delegate = self
        }
    }
#endif
