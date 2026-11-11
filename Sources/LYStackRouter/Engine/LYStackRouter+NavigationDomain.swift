#if canImport(UIKit)
    import UIKit

    extension LYStackRouter {
        /// 显式来源必须仍是当前可见导航域的栈顶，不能从被遮挡的旧页面发起导航。
        func isValidOrigin(_ source: UIViewController?) -> Bool {
            guard let source, let navigation = source.navigationController,
                  isOwnedOrigin(source), navigation.presentedViewController == nil,
                  source.presentedViewController == nil else { return false }
            if currentDomain.contains(where: { $0 === navigation }) {
                return host?.routerRootViewController?.presentedViewController == nil
            }
            return isModalNavigation(navigation) && topPresentedNavigation() === navigation
        }

        /// 检查来源归属，允许有效来源暂时被模态覆盖，供等待请求保留意图。
        func isOwnedOrigin(_ source: UIViewController?) -> Bool {
            guard let source, let navigation = source.navigationController else { return false }
            return source.parent != nil && navigation.topViewController === source && originNavigationIsCurrent(navigation)
        }

        /// 解析本次请求使用的导航栈；显式来源消失时不回退到活跃栈。
        func navigation(for options: LYOpenOptions) -> UINavigationController? {
            if options.hasExplicitOrigin { return options.from?.navigationController }
            return activeNavigation
        }

        func canNavigate(to placement: LYRoutePlacement, options: LYOpenOptions) -> Bool {
            guard !stopped, currentExecution == nil, let host, host.isRouterReady else { return false }
            guard let navigation = navigation(for: options) else { return false }
            if options.hasExplicitOrigin, !isValidOrigin(options.from) { return false }
            if isModalNavigation(navigation) {
                return placement == .current && topPresentedNavigation() === navigation
                    && Self.isIdle(navigation) && host.routerRootViewController?.transitionCoordinator == nil
            }
            return canNavigate(to: placement)
        }

        /// 模态执行只检查自身导航域；普通执行继续使用宿主声明的当前域。
        func executionDomain(_ execution: NavigationExecution) -> [UINavigationController] {
            if execution.isModal { return execution.targetNavigation.map { [$0] } ?? [] }
            return currentDomain
        }

        /// 确认框可以临时覆盖来源，所以这里仅检查归属，不把上层 Alert 当成来源消失。
        func originNavigationIsCurrent(_ navigation: UINavigationController) -> Bool {
            currentDomain.contains { $0 === navigation } || ownsModalNavigation(navigation)
        }

        /// 可操作的模态栈必须仍显示在宿主的真实窗口中。
        func isModalNavigation(_ navigation: UINavigationController) -> Bool {
            navigation.viewIfLoaded?.window != nil && ownsModalNavigation(navigation)
        }

        /// fullScreen 覆盖仅暂时移出来源视图，presentation 链仍能证明归属。
        private func ownsModalNavigation(_ navigation: UINavigationController) -> Bool {
            guard !currentDomain.contains(where: { $0 === navigation }),
                  let root = host?.routerRootViewController,
                  navigation.presentingViewController != nil,
                  belongsToPresentationTree(navigation, root: root),
                  let window = presentationWindow(for: navigation) else { return false }
            if let rootWindow = root.viewIfLoaded?.window { return window === rootWindow }
            guard let windowRoot = window.rootViewController else { return false }
            return belongsToPresentationTree(root, root: windowRoot)
        }

        private func presentationWindow(for controller: UIViewController) -> UIWindow? {
            var candidate: UIViewController? = controller
            var visited = Set<ObjectIdentifier>()
            while let current = candidate, visited.insert(ObjectIdentifier(current)).inserted {
                if let window = current.viewIfLoaded?.window { return window }
                candidate = current.presentedViewController
            }
            return nil
        }

        /// 首次使用模态栈时接入代理与关闭观察；宿主解绑时由统一失效流程拆除。
        func adoptModalNavigation(_ navigation: UINavigationController) {
            guard isModalNavigation(navigation) else { return }
            let identity = ObjectIdentifier(navigation)
            if let existing = managedNavigations[identity], navigation.delegate === existing { return }
            managedNavigations.removeValue(forKey: identity)?.detach()
            let bridge = NavigationEventBridge(navigation: navigation) { [weak self] navigation in
                self?.navigationDidShow(in: navigation)
            }
            managedNavigations[identity] = bridge
            observeModalRemoval(navigation, bridge: bridge)
        }

        private func topPresentedNavigation() -> UINavigationController? {
            guard var controller = host?.routerRootViewController else { return nil }
            var visited = Set<ObjectIdentifier>()
            var modalNavigation: UINavigationController?
            while visited.insert(ObjectIdentifier(controller)).inserted {
                if let presented = controller.presentedViewController {
                    controller = presented
                    modalNavigation = presented as? UINavigationController
                } else if let navigation = controller as? UINavigationController, let top = navigation.topViewController {
                    controller = top
                } else if let tabs = controller as? UITabBarController, let selected = tabs.selectedViewController {
                    controller = selected
                } else {
                    break
                }
            }
            return modalNavigation
        }

        private func belongsToPresentationTree(_ controller: UIViewController, root: UIViewController) -> Bool {
            var candidate: UIViewController? = controller
            var visited = Set<ObjectIdentifier>()
            while let current = candidate, visited.insert(ObjectIdentifier(current)).inserted {
                if current === root { return true }
                candidate = current.parent ?? current.presentingViewController
            }
            return false
        }

        private func observeModalRemoval(_ navigation: UINavigationController, bridge: NavigationEventBridge) {
            guard let presentation = navigation.presentationController else { return }
            let identity = ObjectIdentifier(navigation)
            bridge.presentationObservation = PresentationRemovalObserver(presentation: presentation) { [weak self, weak navigation, weak bridge] in
                guard let self, let bridge, managedNavigations[identity] === bridge else { return }
                // fullScreen 覆盖会暂时移出容器，仍有 presenting 关系时重新观察而不执行退出清理。
                if let navigation, navigation.presentingViewController != nil {
                    observeModalRemoval(navigation, bridge: bridge)
                    return
                }
                let pages = bridge.currentPages
                managedNavigations.removeValue(forKey: identity)
                bridge.detach()
                if let execution = currentExecution, execution.isModal,
                   execution.targetNavigationID == identity, !execution.isDismissing {
                    terminateExecution()
                }
                for page in pages {
                    if let navigation {
                        guard page.parent === navigation else { continue }
                    } else {
                        // 页面可能被业务重新挂载，只有仍然脱离展示树的存活页面才属于本次退出。
                        guard page.parent == nil, page.presentingViewController == nil, page.viewIfLoaded?.window == nil else { continue }
                    }
                    host?.tearDown(page)
                }
                navigationDidStabilize()
            }
        }
    }
#endif
