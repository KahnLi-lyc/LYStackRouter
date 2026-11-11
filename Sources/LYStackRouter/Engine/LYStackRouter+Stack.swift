#if canImport(UIKit)
    import UIKit

    extension LYStackRouter {
        // MARK: - Stack Operations

        func push(_ page: UIViewController, in navigation: UINavigationController, animated: Bool) {
            guard !stopped else { return }
            currentExecution?.phase = .presenting
            navigation.pushViewController(page, animated: animated && navigation.viewIfLoaded?.window != nil)
            markResult(.created)
        }

        /// 栈内已有同身份页面时回到它并返回 true；调用方不得再创建第二个页面。
        func reuse(_ identity: AnyHashable, in navigation: UINavigationController, animated: Bool = true) -> Bool {
            let stack = navigation.viewControllers.map { ($0 as? LYPageIdentifiable)?.routeIdentity }
            switch StackPolicy.decide(target: identity, stack: stack) {
            case .alreadyTop:
                markResult(.alreadyVisible)
                return true
            case let .popTo(index):
                popTo(navigation.viewControllers[index], in: navigation, animated: animated)
                markResult(.reused)
                return true
            case .push:
                return false
            }
        }

        func popTo(_ target: UIViewController, in navigation: UINavigationController, animated: Bool) {
            guard let index = navigation.viewControllers.firstIndex(where: { $0 === target }) else { return }
            replaceStack(Array(navigation.viewControllers.prefix(index + 1)), in: navigation, animated: animated)
        }

        /// 替换导航栈，并在转场结束后只清理确实离开导航栈的页面。
        func replaceStack(_ next: [UIViewController], in navigation: UINavigationController, animated: Bool) {
            currentExecution?.phase = .presenting
            let removed = navigation.viewControllers.filter { old in !next.contains { $0 === old } }
            let epoch = generation
            let operationID = UUID()
            let removal = StackRemoval(pages: removed, owner: host)
            transitionRemovals[operationID] = removal
            navigation.setViewControllers(next, animated: animated && navigation.viewIfLoaded?.window != nil)
            let cleanup: @MainActor () -> Void = { [weak self, weak navigation] in
                self?.transitionRemovals.removeValue(forKey: operationID)
                removal.complete(in: navigation)
                if let self, generation == epoch, !stopped { navigationDidStabilize() }
            }
            if let transition = navigation.transitionCoordinator {
                if !transition.animate(alongsideTransition: nil, completion: { _ in cleanup() }) { cleanup() }
            } else {
                cleanup()
            }
        }

        /// 在宿主的全部导航栈中查找已有页面；找到时切换到它所在的域并回到它。
        func revealExisting(where predicate: (UIViewController) -> Bool) -> Bool {
            guard let host else { return false }
            let navigations = currentExecution?.isModal == true
                ? currentExecution?.targetNavigation.map { [$0] } ?? [] : host.allNavigationControllers
            for navigation in navigations {
                guard let page = navigation.viewControllers.last(where: predicate) else { continue }
                guard navigation.presentedViewController == nil,
                      currentExecution?.hasCompletedTransition(navigation.transitionCoordinator) ?? true else {
                    markResult(.failed(.blocked))
                    return true
                }
                currentExecution?.phase = .presenting
                if currentExecution?.isModal != true { host.reveal(navigation) }
                currentExecution?.targetNavigation = navigation
                if navigation.topViewController === page {
                    markResult(.alreadyVisible)
                } else {
                    popTo(page, in: navigation, animated: false)
                    markResult(.reused)
                }
                return true
            }
            return false
        }

        // MARK: - Back

        /// 返回上一页。可以抢占“准备中”的导航（例如还在等网络），但不打断“展示中”的转场。
        /// 被抢占的导航以 `.contextChanged` 结算，其异步任务被取消；已经交给其他对象的工作不受影响。
        public func navigateBack(from page: UIViewController, in navigation: UINavigationController) {
            // 栈顶页面内的子控制器以所在页面为来源。
            guard let routed = routedPage(for: page), routed.navigation === navigation else { return }
            let page = routed.page
            guard host?.isRouterReady == true, originNavigationIsCurrent(navigation), Self.isIdle(navigation),
                  isModalNavigation(navigation) || isNavigationContextReady,
                  navigation.topViewController === page, page.parent != nil, navigation.viewControllers.count > 1,
                  currentExecution?.phase != .presenting else { return }
            terminateExecution()
            let source = LYRouteSource.user
            _ = execute(kind: nil, source: source, intent: nil, proposed: .reused, options: .init(from: page)) { [self] in
                replaceStack(Array(navigation.viewControllers.dropLast()), in: navigation, animated: true)
                markResult(.reused)
            }
        }
    }
#endif
