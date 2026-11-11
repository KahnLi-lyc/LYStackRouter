#if canImport(UIKit)
    import UIKit

    /// 可注入业务模块的导航能力。操作在主线程执行，返回实际结算结果。
    public struct LYRouteClient<Route: LYRoutable>: Sendable {
        private let openOperation: @MainActor @Sendable (Route, LYOpenOptions) async -> LYOpenResult
        private let urlOperation: @MainActor @Sendable (URL, LYOpenOptions) async -> LYOpenResult
        private let dismissOperation: @MainActor @Sendable (Bool) async -> LYOpenResult

        /// 创建客户端，也可注入测试替身记录路由并返回确定结果。
        public init(
            open: @escaping @MainActor @Sendable (Route, LYOpenOptions) async -> LYOpenResult,
            openURL: @escaping @MainActor @Sendable (URL, LYOpenOptions) async -> LYOpenResult = { _, _ in .failed(.unmatchedURL) },
            dismiss: @escaping @MainActor @Sendable (Bool) async -> LYOpenResult = { _ in .ignored }
        ) {
            openOperation = open
            urlOperation = openURL
            dismissOperation = dismiss
        }

        /// 发起用户导航，选项中的动画与附加值会传入处理器。
        @MainActor @discardableResult
        public func open(_ route: Route, options: LYOpenOptions = .init()) async -> LYOpenResult {
            await openOperation(route, options)
        }

        /// 从业务界面打开 URL，按用户来源重新准入。
        @MainActor @discardableResult
        public func openURL(_ url: URL, options: LYOpenOptions = .init()) async -> LYOpenResult {
            await urlOperation(url, options)
        }

        /// 返回来源页面或关闭来源模态流程。
        @discardableResult
        public func dismiss(animated: Bool = true) async -> LYOpenResult {
            await dismissOperation(animated)
        }
    }

    extension LYStackRouter {
        /// 创建绑定当前会话代次的客户端；绑定页面时仅保留弱引用。
        ///
        /// 登录（nil → 会话）后客户端继续可用；切换账号、退出登录、`resetSession()`、更换宿主或停止路由器后，
        /// 旧客户端一律返回 `.failed(.contextChanged)`，不会跨账号继续导航。
        public func makeClient(from page: UIViewController? = nil) -> LYRouteClient<Route> {
            let scope = RouteClientScope(page: page, sessionEpoch: sessionEpoch)
            return LYRouteClient(open: { [weak self] route, options in
                guard let self, isClientScopeValid(scope) else { return .failed(.contextChanged) }
                return await open(route, options: scopedOptions(options, scope: scope))
            }, openURL: { [weak self] url, options in
                guard let self, isClientScopeValid(scope) else { return .failed(.contextChanged) }
                return await openURL(url, source: .user, options: scopedOptions(options, scope: scope))
            }, dismiss: { [weak self] animated in
                guard let self, isClientScopeValid(scope) else { return .failed(.contextChanged) }
                return await dismissClient(scope, animated: animated)
            })
        }

        private func isClientScopeValid(_ scope: RouteClientScope) -> Bool {
            !Task.isCancelled && !stopped && host != nil && scope.sessionEpoch == sessionEpoch
                && (!scope.hasPage || isValidOrigin(scope.page))
        }

        private func scopedOptions(_ options: LYOpenOptions, scope: RouteClientScope) -> LYOpenOptions {
            guard scope.hasPage else { return options }
            return LYOpenOptions(animated: options.animated, from: scope.page, extras: options.extras)
        }

        private func dismissClient(_ scope: RouteClientScope, animated: Bool) async -> LYOpenResult {
            guard let navigation = scope.page?.navigationController ?? activeNavigation,
                  let page = scope.page ?? navigation.topViewController else { return .ignored }
            guard host?.isRouterReady == true, originNavigationIsCurrent(navigation), Self.isIdle(navigation),
                  isModalNavigation(navigation) || isNavigationContextReady,
                  currentExecution?.phase != .presenting else { return .ignored }
            if navigation.viewControllers.count > 1 {
                terminateExecution()
                let submission = execute(kind: nil, source: .user, intent: nil, proposed: .reused,
                                         options: .init(animated: animated, from: page)) {
                    self.replaceStack(Array(navigation.viewControllers.dropLast()), in: navigation, animated: animated)
                    self.markResult(.reused)
                }
                if let execution = submission.execution { return await execution.value() }
                return submission.immediate
            }
            guard navigation.presentingViewController != nil else { return .ignored }
            terminateExecution()
            let submission = execute(kind: nil, source: .user, intent: nil, proposed: .performed,
                                     options: .init(animated: animated, from: page)) {
                guard let execution = self.currentExecution else { return }
                execution.phase = .presenting
                execution.isDismissing = true
                execution.preparationTask = Task { @MainActor [weak self, weak execution, weak navigation] in
                    guard let self, let execution, let navigation else { return }
                    await awaitUICompletion { completion in navigation.dismiss(animated: animated, completion: completion) }
                    guard isCurrent(execution) else { return }
                    markResult(navigation.presentingViewController == nil ? .performed : .failed(.blocked))
                }
            }
            if let execution = submission.execution { return await execution.value() }
            return submission.immediate
        }
    }

    /// 将弱来源与创建时的会话代次封装在主线程对象中，客户端本身可安全注入并发业务代码。
    @MainActor
    private final class RouteClientScope {
        weak var page: UIViewController?
        let hasPage: Bool
        let sessionEpoch: UUID

        init(page: UIViewController?, sessionEpoch: UUID) {
            self.page = page
            hasPage = page != nil
            self.sessionEpoch = sessionEpoch
        }
    }
#endif
