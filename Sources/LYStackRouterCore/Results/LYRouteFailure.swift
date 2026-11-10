/// 一次导航失败的原因。
public enum LYRouteFailure: Hashable, Sendable {
    /// 没有任何模块注册该路由。
    case unregistered
    /// 路由被禁用、降级或尚未开放。
    case unavailable
    /// 路由参数未通过校验。
    case invalidParameter
    /// 外部来源请求了未放开外部调用的路由。
    case notExternal
    /// URL 无法解析为任何已注册的路由。
    case unmatchedURL
    /// 被拦截器拒绝，附带拦截器给出的原因标识。
    case rejected(String)
    /// 宿主正在转场或被弹窗遮挡，暂时无法执行。
    case blocked
    /// 执行期间被返回抢占、宿主更换或会话变化，原请求作废。
    case contextChanged
    /// 业务权限不足。
    case permissionDenied
    /// 路由器已停止。
    case stopped
}
