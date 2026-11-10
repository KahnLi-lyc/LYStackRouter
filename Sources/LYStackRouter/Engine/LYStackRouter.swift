#if canImport(UIKit)
    import UIKit

    /// 每个窗口一个的导航执行者。由宿主创建并持有，通过注入使用，没有单例。
    ///
    /// 执行语义：
    /// - 一次导航只结算一次；用户在导航进行中的重复点击被忽略。
    /// - 返回可以抢占“准备中”的导航（例如还在等网络），但不能打断“展示中”的转场。
    /// - 外部请求遇到暂时受阻时只保留最近一个，宿主稳定后自动执行。
    /// - 只清理确实离开导航栈的页面；交互返回取消时不清理。
    /// - 宿主更换、会话重置后，旧导航的迟到回调一律作废。
    @MainActor
    public final class LYStackRouter<Route: LYRoutable> {
        // MARK: - Properties

        /// 构建完成的注册表。
        public let registry: LYStackRouteRegistry<Route>
        /// URL 入口配置；为 nil 时不解析 URL。
        public let urlConfiguration: LYURLConfiguration?
        /// 远程下发的重写与降级配置，可随时整体替换。
        public var rewrite: LYRouteRewrite
        /// 参与构建的模块标识，按登记顺序排列；用于诊断与确认自动发现的结果。
        public private(set) var moduleIDs: [String] = []

        let interceptors: [LYRouteInterceptor<Route>]
        let observers: [any LYRouteObserver<Route>]
        let fallback: LYRouteFallback<Route>?

        weak var host: (any LYRouterHost)?
        /// 最近一次确认的会话标识，用于区分“登录”（nil → A）与“切换账号”（A → B）。
        var knownSessionID: String?
        let allowsUnregistered: Bool
        var generation = UUID()
        var currentExecution: NavigationExecution?
        var stopped = false
        var sequence: UInt64 = 0
        var pending: Pending?
        var redirectDepth = 0
        var modalObserver: PresentationRemovalObserver?
        /// 等待请求正在观察的导航转场；同一转场只注册一次完成回调。
        var pendingTransitionID: ObjectIdentifier?
        var confirmationObservation: PresentationRemovalView?
        /// 只持有进行中栈操作的移出快照，转场结束或宿主解绑时取走。
        var transitionRemovals: [UUID: [UIViewController]] = [:]
        var transitionWaiters: [UUID: CheckedContinuation<Void, Never>] = [:]

        /// 确认框的展示方式；返回 false 表示 UIKit 没有接受展示。
        /// 参数依次为确认框、导航栈、确认动作（与确认按钮相同）、展示完成回调。测试可替换以直接触发确认。
        var confirmationPresenter: (
            UIAlertController,
            UINavigationController,
            @escaping @MainActor () -> Void,
            @escaping @MainActor () -> Void
        ) -> Bool = { alert, navigation, _, onPresented in
            // UIKit 在主线程调用展示完成回调。
            navigation.present(alert, animated: true) { MainActor.assumeIsolated { onPresented() } }
            return alert.presentingViewController != nil
        }

        /// 外部请求在受阻期间保存的值，不保存页面、Store 或闭包。
        struct Pending {
            let route: Route
            let source: LYRouteSource
            let sequence: UInt64
            var sessionID: String?
        }

        // MARK: - Initialization

        init(
            registry: LYStackRouteRegistry<Route>,
            urlConfiguration: LYURLConfiguration?,
            rewrite: LYRouteRewrite,
            interceptors: [LYRouteInterceptor<Route>],
            observers: [any LYRouteObserver<Route>],
            fallback: LYRouteFallback<Route>?,
            allowsUnregistered: Bool
        ) {
            self.registry = registry
            self.allowsUnregistered = allowsUnregistered
            self.urlConfiguration = urlConfiguration
            self.rewrite = rewrite
            self.interceptors = interceptors
            self.observers = observers
            self.fallback = fallback
        }

        /// 创建模块、收集登记并构建路由器。
        ///
        /// - Parameters:
        ///   - host: 宿主，可稍后通过 `attach` 绑定。
        ///   - modules: 参与的模块。
        ///   - environment: 模块依赖。
        ///   - interceptors: 拦截器，按优先级执行。
        ///   - observers: 只读观察者。
        ///   - url: URL 入口配置。
        ///   - rewrite: 初始重写与降级配置。
        ///   - fallback: 兜底，用于占位、降级路由；`allowsUnregistered` 为 true 时也处理未注册的路由。
        ///   - allowsUnregistered: 是否允许路由种类未被注册。默认 false：任何种类缺少注册都会让构建失败，
        ///     自动发现漏掉模块时也能立即发现。模块 Demo 只装部分模块时设为 true，并提供兜底。
        public static func build(
            host: (any LYRouterHost)? = nil,
            modules: LYRouteModuleSet<Route>,
            environment: LYRouteEnvironment = LYRouteEnvironment(),
            interceptors: [LYRouteInterceptor<Route>] = [],
            observers: [any LYRouteObserver<Route>] = [],
            url: LYURLConfiguration? = nil,
            rewrite: LYRouteRewrite = .none,
            fallback: LYRouteFallback<Route>? = nil,
            allowsUnregistered: Bool = false
        ) throws -> LYStackRouter {
            let types = modules.resolve()
            var seen: [String: Int] = [:]
            for type in types {
                seen[type.moduleID, default: 0] += 1
            }
            let duplicated = seen.filter { $0.value > 1 }.keys.sorted()
            guard duplicated.isEmpty else { throw LYRouteBuildError.duplicateModule(duplicated) }

            var builder = LYStackRouteRegistry<Route>.Builder()
            for type in types {
                let module: any LYRouteModule<Route>
                do {
                    module = try type.init(environment: environment)
                } catch let missing as LYRouteEnvironment.MissingDependency {
                    throw LYRouteBuildError.missingDependency(module: type.moduleID, type: missing.type)
                } catch {
                    throw LYRouteBuildError.moduleInitializationFailed(
                        module: type.moduleID,
                        reason: String(describing: error)
                    )
                }
                builder.moduleID = type.moduleID
                module.register(into: &builder)
            }
            let registry = try builder.build(requireExhaustive: !allowsUnregistered)
            let router = LYStackRouter(
                registry: registry,
                urlConfiguration: url,
                rewrite: rewrite,
                interceptors: interceptors,
                observers: observers,
                fallback: fallback,
                allowsUnregistered: allowsUnregistered
            )
            // 不写 `map(\.moduleID)`：Swift 6.4.2 对存在类型元类型的 key path 会在 SILGen 阶段崩溃。
            // swiftformat:disable:next preferKeyPath
            router.moduleIDs = types.map { $0.moduleID }
            if let host { router.attach(host) }
            return router
        }

        // MARK: - Public

        /// 绑定宿主。更换宿主会使旧宿主上的导航作废；外部等待中的请求保留。
        public func attach(_ host: any LYRouterHost) {
            guard !stopped else { return }
            if let old = self.host, old !== host { detach(old) }
            self.host = host
            knownSessionID = host.routerSessionID
            if let source = host as? LYNavigationEventSource {
                source.onNavigationDidShow = { [weak self] navigation in self?.navigationDidShow(in: navigation) }
            }
            navigationDidStabilize()
        }

        /// 解绑宿主。只有当前绑定的宿主才能解绑，旧宿主迟到的解绑不影响新宿主。
        public func detach(_ host: any LYRouterHost) {
            guard self.host === host else { return }
            invalidateExecution()
            (host as? LYNavigationEventSource)?.onNavigationDidShow = nil
            self.host = nil
        }

        /// 宿主会话变化后调用。
        ///
        /// - 从无会话变为有会话（登录）：保留等待中的外部请求并绑定到新会话，随后尝试执行。
        /// - 从一个会话变为另一个会话，或退出登录：等同 `resetSession()`，清空等待请求。
        /// 两种情况都会使进行中的导航作废。
        public func sessionDidChange() {
            let current = host?.routerSessionID
            guard current != knownSessionID else { return }
            let previous = knownSessionID
            knownSessionID = current
            if previous == nil, let current {
                if pending?.sessionID == nil { pending?.sessionID = current }
                invalidateExecution()
                navigationDidStabilize()
            } else {
                resetSession()
            }
        }

        /// 无条件清空外部等待请求，并使进行中的导航作废。退出登录、切换账号时使用。
        public func resetSession() {
            pending = nil
            knownSessionID = host?.routerSessionID
            invalidateExecution()
        }

        /// 停止路由器：之后的请求一律以 `.stopped` 失败。重复调用安全。
        public func tearDown() {
            guard !stopped else { return }
            stopped = true
            resetSession()
            host = nil
        }

        /// 用户请求：在当前 MainActor 轮次同步准入，适合按钮回调。异步结果请用 `open`。
        @discardableResult
        public func request(_ route: Route) -> LYOpenResult {
            submit(route, source: .user).immediate
        }

        /// 打开路由并等待本次导航结算。
        @discardableResult
        public func open(_ route: Route, source: LYRouteSource = .user) async -> LYOpenResult {
            let submission = submit(route, source: source)
            if let execution = submission.execution { return await execution.value() }
            return submission.immediate
        }

        /// 打开 URL：先应用重写，再解析为路由；不属于本 App 或无法匹配时以 `.unmatchedURL` 失败。
        @discardableResult
        public func openURL(_ url: URL, source: LYRouteSource = .deepLink) async -> LYOpenResult {
            guard let route = route(for: url) else {
                notifySettle(nil, source: source, result: .failed(.unmatchedURL))
                return .failed(.unmatchedURL)
            }
            return await open(route, source: source)
        }

        /// 把 URL 解析为路由；不打开。
        public func route(for url: URL) -> Route? {
            guard let urlConfiguration else { return nil }
            return registry.route(for: url, configuration: urlConfiguration, rewrite: rewrite)
        }

        /// 为路由生成 URL；`universalLinkHost` 为 nil 时使用自定义 scheme。
        public func url(for route: Route, universalLinkHost: String? = nil) -> URL? {
            guard let urlConfiguration else { return nil }
            return registry.url(for: route, configuration: urlConfiguration, universalLinkHost: universalLinkHost)
        }

        /// 当前是否有导航正在进行。
        public var isNavigating: Bool {
            currentExecution != nil
        }

        /// 等待当前导航结算；没有进行中的导航时返回 nil。主要用于测试与示例。
        @discardableResult
        public func waitForNavigation() async -> LYOpenResult? {
            await currentExecution?.value()
        }

        // MARK: - Internal

        /// 当前活跃导航栈。
        var activeNavigation: UINavigationController? {
            host?.activeNavigationController
        }
    }
#endif
