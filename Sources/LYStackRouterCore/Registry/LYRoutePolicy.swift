/// 路由的开放状态。
public enum LYRouteStatus: Hashable, Sendable {
    /// 正常开放。
    case implemented
    /// 已登记但只展示占位，用于尚未完成的页面。
    case placeholder
    /// 已禁用，请求一律以 `.unavailable` 失败。
    case disabled
}

/// 注册时为一个路由种类声明的策略。
@MainActor
public struct LYRoutePolicy<Route: LYRoutable> {
    /// 开放状态。
    public var status: LYRouteStatus
    /// 目标域，由宿主解释；默认当前域。
    public var placement: LYRoutePlacement
    /// 是否允许推送、深链、H5 等外部来源打开。默认 false，需要显式放开。
    public var allowsExternal: Bool
    /// 是否需要有效会话（例如已登录）。由会话拦截器读取。
    public var requiresSession: Bool
    /// 参数校验。返回 false 时以 `.invalidParameter` 失败，不产生任何导航副作用。
    public var validate: @MainActor (Route) -> Bool

    /// 创建策略。
    public init(
        status: LYRouteStatus = .implemented,
        placement: LYRoutePlacement = .current,
        allowsExternal: Bool = false,
        requiresSession: Bool = false,
        validate: @escaping @MainActor (Route) -> Bool = { _ in true }
    ) {
        self.status = status
        self.placement = placement
        self.allowsExternal = allowsExternal
        self.requiresSession = requiresSession
        self.validate = validate
    }
}

/// 处理器的类型：页面会改变导航栈，动作不会。
public enum LYRouteHandlerKind: Hashable, Sendable {
    /// 打开或复用一个页面。
    case page
    /// 执行一个不改变导航栈的动作，例如弹出面板。
    case action
}
