#if canImport(UIKit)
    import UIKit

    /// 处理器执行一次导航时使用的上下文。
    ///
    /// 处理器在取得执行权后同步运行；需要等网络等异步准备时使用 `prepare`。
    /// 页面里的按钮等后续操作应使用 `open`（重新准入）而不是 `continueNavigation`。
    @MainActor
    public struct LYRouteContext<Route: LYRoutable> {
        // MARK: - Properties

        /// 本次导航的路由。
        public let route: Route
        /// 本次导航的来源。
        public let source: LYRouteSource

        private weak var router: LYStackRouter<Route>?
        private weak var execution: NavigationExecution?

        // MARK: - Initialization

        init(router: LYStackRouter<Route>, route: Route, source: LYRouteSource, execution: NavigationExecution? = nil) {
            self.router = router
            self.route = route
            self.source = source
            self.execution = execution
        }

        // MARK: - Public

        /// 当前活跃导航栈。
        public var navigationController: UINavigationController? {
            router?.activeNavigation
        }

        /// 展示页面：带身份时先在当前导航栈查找，已有就回到最近的实例，否则创建并 push。
        ///
        /// 宿主的 `customShow` 可以接管展示（例如放进分栏容器）。`make` 最多被调用一次。
        public func show(identity: AnyHashable? = nil, animated: Bool = true, _ make: () -> UIViewController) {
            guard let router, let navigation = router.activeNavigation else {
                router?.markResult(.failed(.unavailable))
                return
            }
            if let identity, router.reuse(identity, in: navigation) { return }
            // 宿主可能不调用、也可能调用页面构造；保证 make 最多执行一次。
            withoutActuallyEscaping(make) { make in
                var made: UIViewController?
                let page: () -> UIViewController = {
                    if let made { return made }
                    let created = make()
                    made = created
                    return created
                }
                if let result = router.host?.customShow(page(), identity: identity, in: navigation) {
                    router.currentExecution?.phase = .presenting
                    router.markResult(result)
                    return
                }
                router.push(page(), in: navigation, animated: animated)
            }
        }

        /// 以模态方式展示页面。
        public func present(_ page: UIViewController, animated: Bool = true) {
            guard let router, let navigation = router.activeNavigation else {
                router?.markResult(.failed(.unavailable))
                return
            }
            router.currentExecution?.phase = .presenting
            navigation.present(page, animated: animated && navigation.viewIfLoaded?.window != nil)
            router.markResult(.created)
        }

        /// 异步准备，例如先拉取数据再决定展示。
        ///
        /// 准备期间用户点返回会抢占本次导航：任务被取消，结果为 `.contextChanged`。
        /// 准备完成后必须先 `await context.isStillValid()`，返回 true 才能继续展示。
        /// `work` 抛出错误时本次导航以 `.unavailable` 失败。
        public func prepare(_ work: @escaping @MainActor (LYRouteContext<Route>) async throws -> Void) {
            guard let router, let navigation = router.activeNavigation, let origin = navigation.topViewController,
                  let execution = router.bindOrigin(source: origin, navigation: navigation) else { return }
            let context = LYRouteContext(router: router, route: route, source: source, execution: execution)
            execution.preparationTask = Task { @MainActor [weak router, weak execution] in
                do {
                    try await work(context)
                } catch {
                    guard !Task.isCancelled, let router, let execution, router.isCurrent(execution) else { return }
                    router.markResult(.failed(.unavailable))
                }
            }
        }

        /// 异步准备返回后检查本次导航是否仍可继续：没有被抢占、来源仍在栈顶、没有弹窗或转场。
        public func isStillValid() async -> Bool {
            guard let router, let execution else { return false }
            return await router.validateContinuation(execution)
        }

        /// 通用确认门：展示确认框，本次导航以 `.awaitingConfirmation` 结算。
        ///
        /// 用户确认后，在来源页面仍可见的前提下重新取得执行权，再调用 `onConfirm`。取消则什么也不做。
        /// UIKit 拒绝展示确认框时，本次导航以 `.blocked` 结算，不会一直占用执行权。
        public func confirm(
            title: String?,
            message: String?,
            confirmTitle: String,
            cancelTitle: String,
            isDestructive: Bool = false,
            onConfirm: @escaping @MainActor (LYRouteContext<Route>) -> Void
        ) {
            guard let router, let navigation = router.activeNavigation, navigation.presentedViewController == nil,
                  let origin = navigation.topViewController,
                  let execution = router.bindOrigin(source: origin, navigation: navigation) else { return }
            execution.phase = .presenting
            router.markResult(.awaitingConfirmation)
            let state = ConfirmationState()
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in state.handled = true })
            let route = route
            let source = source
            alert.addAction(UIAlertAction(title: confirmTitle, style: isDestructive ? .destructive : .default) {
                [weak router, weak navigation, weak origin, weak alert] _ in
                guard !state.handled else { return }
                state.handled = true
                Task { @MainActor [weak router, weak navigation, weak origin, weak alert] in
                    guard await execution.value() == .awaitingConfirmation, let router else { return }
                    // 确认动作早于系统关闭完成；等确认框真正关闭后再重新取得执行权。
                    if let transition = alert?.transitionCoordinator ?? navigation?.transitionCoordinator {
                        await router.awaitTransition(transition)
                    }
                    if let alert, alert.presentingViewController != nil {
                        await router.awaitUICompletion { completion in alert.dismiss(animated: false, completion: completion) }
                    }
                    guard let navigation, let origin, router.isOriginStillPresented(navigation, source: origin) else {
                        return
                    }
                    router.performUserNavigation(route: route, source: source, onConfirm)
                }
            })
            let accepted = router.confirmationPresenter(alert, navigation) { [weak router] in
                router?.confirmationDidPresent(execution)
            }
            if accepted {
                router.observeConfirmationRemoval(alert, execution: execution)
            } else {
                router.confirmationDidFailToPresent(execution)
            }
        }

        /// 在处理器内同步继续到另一个路由，复用本次执行，不重新准入。只能在处理器同步执行期间使用。
        public func continueNavigation(to route: Route) {
            router?.continueNavigation(to: route, source: source)
        }

        /// 发起一次新的用户导航，适合页面按钮回调；导航进行中时被忽略。
        @discardableResult
        public func open(_ route: Route) -> LYOpenResult {
            router?.request(route) ?? .failed(.stopped)
        }

        /// 返回上一页，可以抢占准备中的导航。
        public func back(from page: UIViewController) {
            guard let router, let navigation = page.navigationController else { return }
            router.navigateBack(from: page, in: navigation)
        }

        /// 用给定页面替换当前导航栈，只清理确实离开栈的页面。
        public func replaceStack(_ pages: [UIViewController], animated: Bool = true) {
            guard let router, let navigation = router.activeNavigation else { return }
            router.replaceStack(pages, in: navigation, animated: animated)
            router.markResult(.created)
        }

        /// 在宿主的全部导航栈中查找已有页面（例如会话型页面），找到时切换到它所在的域并回到它。
        /// 返回 false 表示没有找到，调用方应自行创建。
        public func revealExisting(where predicate: (UIViewController) -> Bool) -> Bool {
            router?.revealExisting(where: predicate) ?? false
        }

        /// 动作路由完成时调用，结果为 `.performed`。
        public func markPerformed() {
            router?.markResult(.performed)
        }

        /// 以指定失败结束本次导航（不改变导航栈）。
        public func fail(_ failure: LYRouteFailure) {
            router?.markResult(.failed(failure))
        }
    }

    /// 确认框的一次性处理标记，取消与确认只会生效一个。
    @MainActor
    private final class ConfirmationState {
        var handled = false
    }
#endif
