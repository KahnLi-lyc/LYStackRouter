#if canImport(UIKit)
    import UIKit

    /// 处理器执行一次导航时使用的上下文。
    ///
    /// 处理器在取得执行权后同步运行；需要等网络等异步准备时使用 `prepare`。
    /// 页面里的按钮等后续操作应使用 `open`（重新准入）而不是 `continueNavigation`。
    ///
    /// 上下文绑定创建它的那次执行：`show`、`present`、`prepare`、`confirm`、`replaceStack`、`revealExisting`、
    /// `continueNavigation`、`markPerformed`、`fail` 只在该执行仍是当前执行时生效，之后调用会被忽略。
    /// `open` 与 `back` 不受此限制，页面在整个生命周期内都可以用它们发起新导航。
    @MainActor
    public struct LYRouteContext<Route: LYRoutable> {
        // MARK: - Properties

        /// 本次导航的路由。
        public let route: Route
        /// 本次导航的来源。
        public let source: LYRouteSource

        /// 本次执行的打开选项。
        public let options: LYOpenOptions

        private weak var router: LYStackRouter<Route>?
        private weak var execution: NavigationExecution?
        private weak var targetNavigation: UINavigationController?

        // MARK: - Initialization

        init(router: LYStackRouter<Route>, route: Route, source: LYRouteSource, execution: NavigationExecution? = nil) {
            self.router = router
            self.route = route
            self.source = source
            self.execution = execution
            targetNavigation = execution?.targetNavigation
            options = execution?.options ?? .init()
        }

        // MARK: - Public

        /// 创建本上下文时绑定的目标导航栈；以弱引用保留，结算后仍可查询。
        public var navigationController: UINavigationController? {
            targetNavigation
        }

        /// 展示页面：带身份时先在当前导航栈查找，已有就回到最近的实例，否则创建并 push。
        ///
        /// 宿主的 `customShow` 可以接管展示（例如放进分栏容器）。`make` 最多被调用一次。
        public func show(identity: AnyHashable? = nil, animated: Bool? = nil, _ make: () -> UIViewController) {
            guard isCurrentExecution else { return }
            guard let router, let navigation = execution?.targetNavigation else {
                router?.markResult(.failed(.unavailable))
                return
            }
            if let identity, router.reuse(identity, in: navigation, animated: animated ?? options.animated) { return }
            // 宿主可能不调用、也可能调用页面构造；保证 make 最多执行一次。
            withoutActuallyEscaping(make) { make in
                var made: UIViewController?
                let page: () -> UIViewController = {
                    if let made { return made }
                    let created = make()
                    made = created
                    return created
                }
                if let result = router.host?.customShow(page(), identity: identity, in: navigation, options: resolvedOptions(animated)) {
                    router.currentExecution?.phase = .presenting
                    router.markResult(result)
                    return
                }
                router.push(page(), in: navigation, animated: animated ?? options.animated)
            }
        }

        /// 以模态方式展示页面。
        public func present(_ page: UIViewController, animated: Bool? = nil) {
            guard isCurrentExecution else { return }
            guard let router, let navigation = execution?.targetNavigation else {
                router?.markResult(.failed(.unavailable))
                return
            }
            router.currentExecution?.phase = .presenting
            let epoch = router.generation
            navigation.present(page, animated: (animated ?? options.animated) && navigation.viewIfLoaded?.window != nil) { [weak router, weak page] in
                guard let router, router.isCurrent(epoch), let modal = page as? UINavigationController else { return }
                router.adoptModalNavigation(modal)
            }
            if let modal = page as? UINavigationController { router.adoptModalNavigation(modal) }
            router.markResult(page.presentingViewController == nil ? .failed(.blocked) : .created)
        }

        /// 异步准备，例如先拉取数据再决定展示。
        ///
        /// 准备期间用户点返回会抢占本次导航：任务被取消，结果为 `.contextChanged`。
        /// 准备完成后必须先 `await context.isStillValid()`，返回 true 才能继续展示。
        /// `work` 抛出错误时本次导航以 `.unavailable` 失败。
        public func prepare(_ work: @escaping @MainActor (LYRouteContext<Route>) async throws -> Void) {
            guard isCurrentExecution, let router, let navigation = execution?.targetNavigation, let origin = navigation.topViewController,
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
            guard isCurrentExecution, let router, let navigation = execution?.targetNavigation, navigation.presentedViewController == nil,
                  let origin = navigation.topViewController,
                  let execution = router.bindOrigin(source: origin, navigation: navigation) else { return }
            execution.phase = .presenting
            router.markResult(.awaitingConfirmation)
            let state = ConfirmationState()
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in state.handled = true })
            let route = route
            let source = source
            let options = options
            let confirmAction: @MainActor () -> Void = { [weak router, weak navigation, weak origin, weak alert] in
                guard !state.handled else { return }
                state.handled = true
                Task { @MainActor [weak router, weak navigation, weak origin, weak alert] in
                    // 确认框结算后执行已结束；每个挂起点之后都核对代次与会话，会话变化后不再继续。
                    guard await execution.value() == .awaitingConfirmation, let router,
                          router.isConfirmationContextValid(execution) else { return }
                    // 确认动作早于系统关闭完成；等确认框真正关闭后再重新取得执行权。
                    if let transition = alert?.transitionCoordinator ?? navigation?.transitionCoordinator {
                        await router.awaitTransition(transition)
                        guard router.isConfirmationContextValid(execution) else { return }
                    }
                    if let alert, alert.presentingViewController != nil {
                        await router.awaitUICompletion { completion in alert.dismiss(animated: false, completion: completion) }
                        guard router.isConfirmationContextValid(execution) else { return }
                    }
                    guard let navigation, let origin, router.isOriginStillPresented(navigation, source: origin) else {
                        return
                    }
                    // 跨域打开后，确认框的来源属于目标栈；后续执行从已确认的页面重新准入。
                    let continuationOptions = LYOpenOptions(animated: options.animated, from: origin, extras: options.extras)
                    router.performUserNavigation(route: route, source: source, options: continuationOptions, onConfirm)
                }
            }
            alert.addAction(UIAlertAction(title: confirmTitle, style: isDestructive ? .destructive : .default) { _ in
                confirmAction()
            })
            let accepted = router.confirmationPresenter(alert, navigation, confirmAction) { [weak router] in
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
            guard isCurrentExecution else { return }
            router?.continueNavigation(to: route, source: source)
        }

        /// 发起一次新的用户导航，适合页面按钮回调；导航进行中时被忽略。
        @discardableResult
        public func open(_ route: Route, options: LYOpenOptions = .init()) -> LYOpenResult {
            router?.request(route, options: options) ?? .failed(.stopped)
        }

        /// 返回上一页，可以抢占准备中的导航。
        public func back(from page: UIViewController) {
            guard let router, let navigation = page.navigationController else { return }
            router.navigateBack(from: page, in: navigation)
        }

        /// 用给定页面替换当前导航栈，只清理确实离开栈的页面。
        public func replaceStack(_ pages: [UIViewController], animated: Bool? = nil) {
            guard isCurrentExecution, let router, let navigation = execution?.targetNavigation else { return }
            router.replaceStack(pages, in: navigation, animated: animated ?? options.animated)
            router.markResult(.created)
        }

        /// 在宿主的全部导航栈中查找已有页面（例如会话型页面），找到时切换到它所在的域并回到它。
        /// 返回 false 表示没有找到，调用方应自行创建。
        public func revealExisting(where predicate: (UIViewController) -> Bool) -> Bool {
            guard isCurrentExecution else { return false }
            return router?.revealExisting(where: predicate) ?? false
        }

        /// 动作路由完成时调用，结果为 `.performed`。
        public func markPerformed() {
            guard isCurrentExecution else { return }
            router?.markResult(.performed)
        }

        /// 以指定失败结束本次导航（不改变导航栈）。
        public func fail(_ failure: LYRouteFailure) {
            guard isCurrentExecution else { return }
            router?.markResult(.failed(failure))
        }

        /// 创建可供页面与业务依赖注入的客户端，绑定当前宿主与会话代次。
        public func makeClient(from page: UIViewController? = nil) -> LYRouteClient<Route> {
            router?.makeClient(from: page) ?? LYRouteClient(
                open: { _, _ in .failed(.contextChanged) },
                openURL: { _, _ in .failed(.contextChanged) },
                dismiss: { _ in .failed(.contextChanged) }
            )
        }

        // MARK: - Private

        private func resolvedOptions(_ animated: Bool?) -> LYOpenOptions {
            var value = options
            if let animated { value.animated = animated }
            return value
        }

        /// 创建本上下文的执行仍是路由器的当前执行。执行结算或被抢占后，单次执行的操作一律忽略。
        private var isCurrentExecution: Bool {
            guard let router, let execution else { return false }
            return router.currentExecution === execution
        }
    }

    /// 确认框的一次性处理标记，取消与确认只会生效一个。
    @MainActor
    private final class ConfirmationState {
        var handled = false
    }
#endif
