#if canImport(UIKit)
    import UIKit

    /// 模态导航栈的事件桥；只接管导航事件，其余可选代理能力转发给原代理。
    @MainActor
    final class NavigationEventBridge: NSObject, UINavigationControllerDelegate {
        weak var navigation: UINavigationController?
        private weak var previousDelegate: (any UINavigationControllerDelegate)?
        var presentationObservation: PresentationRemovalObserver?
        private var onDidShow: ((UINavigationController) -> Void)?

        init(navigation: UINavigationController, onDidShow: @escaping (UINavigationController) -> Void) {
            self.navigation = navigation
            previousDelegate = navigation.delegate
            self.onDidShow = onDidShow
            super.init()
            navigation.delegate = self
        }

        /// 只有代理仍属于本桥时才恢复，业务后来更换的代理不会被覆盖。
        func detach() {
            presentationObservation?.detach()
            presentationObservation = nil
            onDidShow = nil
            if let navigation, navigation.delegate === self { navigation.delegate = previousDelegate }
        }

        func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
            previousDelegate?.navigationController?(navigationController, willShow: viewController, animated: animated)
        }

        func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
            previousDelegate?.navigationController?(navigationController, didShow: viewController, animated: animated)
            onDidShow?(navigationController)
        }

        /// UIKit 在主线程查询导航代理能力，保持原代理的可选方法可见性。
        override nonisolated func responds(to selector: Selector!) -> Bool {
            MainActor.assumeIsolated {
                super.responds(to: selector) || previousDelegate?.responds(to: selector) == true
            }
        }

        /// 未被本桥实现的动画、交互与方向代理方法仍由原代理接收。
        override nonisolated func forwardingTarget(for selector: Selector!) -> Any? {
            MainActor.assumeIsolated {
                previousDelegate
            }
        }
    }
#endif
