/// 导航请求的来源。
///
/// 来源只影响两件事：暂时无法执行时是否保留请求，以及是否检查外部白名单；它不改变业务权限。
public enum LYRouteSource: Hashable, Sendable {
    /// 当前界面上的用户操作。受阻时直接忽略，不排队。
    case user
    /// 推送通知。
    case push
    /// URL Scheme 或 Universal Link。
    case deepLink
    /// H5 页面通过桥接发起的请求。
    case web
    /// 接入方自定义的外部来源。
    case custom(String)

    /// 是否为外部来源。外部来源只能打开 `allowsExternal` 为 true 的路由，受阻时保留最近一个请求。
    public var isExternal: Bool {
        self != .user
    }
}
