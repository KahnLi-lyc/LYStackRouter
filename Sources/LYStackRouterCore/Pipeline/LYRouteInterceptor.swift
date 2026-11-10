/// 拦截器的决策。拦截在切换容器、创建页面等任何副作用之前同步执行。
public enum LYInterceptDecision<Route: LYRoutable>: Hashable, Sendable {
    /// 放行，交给下一个拦截器或执行。
    case proceed
    /// 改为打开另一个路由，例如未登录时跳到登录页。重定向后的路由重新经过完整流程。
    case redirect(Route)
    /// 拒绝，附带失败原因。
    case reject(LYRouteFailure)
    /// 暂时无法执行。外部请求进入等待，用户请求被忽略。
    case deferUntilReady
}

/// 交给拦截器判断的请求。
public struct LYInterceptRequest<Route: LYRoutable>: Sendable {
    /// 目标路由。
    public let route: Route
    /// 请求来源。
    public let source: LYRouteSource
    /// 该路由是否声明需要会话。
    public let requiresSession: Bool
}

/// 带优先级的同步拦截器。优先级高的先执行；同优先级按登记顺序。
@MainActor
public struct LYRouteInterceptor<Route: LYRoutable> {
    // MARK: - Properties

    /// 名称，用于诊断。
    public let name: String
    /// 优先级，数值越大越先执行。
    public let priority: Int
    /// 作用的路由种类；nil 表示全部。
    public let kinds: Set<Route.Kind>?
    /// 决策闭包。
    public let decide: @MainActor (LYInterceptRequest<Route>) -> LYInterceptDecision<Route>

    // MARK: - Initialization

    /// 创建拦截器。
    public init(
        name: String,
        priority: Int = 0,
        kinds: Set<Route.Kind>? = nil,
        decide: @escaping @MainActor (LYInterceptRequest<Route>) -> LYInterceptDecision<Route>
    ) {
        self.name = name
        self.priority = priority
        self.kinds = kinds
        self.decide = decide
    }

    // MARK: - Public

    /// 会话拦截器：路由声明 `requiresSession` 且会话无效时，返回 `whenInactive` 的决策。
    ///
    /// - Parameters:
    ///   - isActive: 读取当前会话是否有效。
    ///   - whenInactive: 会话无效时的决策，默认等待会话就绪（外部请求保留，用户请求忽略）。
    public static func session(
        priority: Int = 1000,
        isActive: @escaping @MainActor () -> Bool,
        whenInactive: LYInterceptDecision<Route> = .deferUntilReady
    ) -> LYRouteInterceptor {
        LYRouteInterceptor(name: "session", priority: priority) { request in
            request.requiresSession && !isActive() ? whenInactive : .proceed
        }
    }

    // MARK: - Internal

    /// 按优先级排序并执行，返回第一个非放行的决策。
    package static func evaluate(
        _ interceptors: [LYRouteInterceptor],
        request: LYInterceptRequest<Route>
    ) -> LYInterceptDecision<Route> {
        let ordered = interceptors.enumerated().sorted { lhs, rhs in
            lhs.element.priority != rhs.element.priority ? lhs.element.priority > rhs.element.priority : lhs.offset < rhs.offset
        }
        for (_, interceptor) in ordered {
            if let kinds = interceptor.kinds, !kinds.contains(request.route.kind) { continue }
            let decision = interceptor.decide(request)
            if decision != .proceed { return decision }
        }
        return .proceed
    }
}

package extension LYInterceptRequest {
    /// 构造请求；仅供引擎调用。
    init(route: Route, source: LYRouteSource, policyRequiresSession: Bool) {
        self.route = route
        self.source = source
        requiresSession = policyRequiresSession
    }
}
