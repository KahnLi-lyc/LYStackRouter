/// 导航观察者，只用于埋点与日志，不能改变执行结果。
///
/// 回调只携带路由种类、来源与结果，不携带 URL 原文，避免泄露 Token 等敏感参数。
/// 全部方法都有默认实现，遵循时需声明 `typealias Route = 你的路由类型`。
@MainActor
public protocol LYRouteObserver<Route>: AnyObject {
    /// 观察的路由类型。
    associatedtype Route: LYRoutable

    /// 请求通过准入、即将执行。
    func routeWillOpen(_ kind: Route.Kind, source: LYRouteSource)
    /// 请求已结算（包括失败、忽略与等待）。`kind` 为 nil 表示 URL 无法解析。
    func routeDidSettle(_ kind: Route.Kind?, source: LYRouteSource, result: LYOpenResult)
    /// 已以 `.deferred` 结算的等待请求被丢弃，不会再执行。每个等待请求最多通知一次。
    func routeDidDropPending(_ kind: Route.Kind, source: LYRouteSource, reason: LYPendingDropReason)
}

public extension LYRouteObserver {
    /// 默认不处理。
    func routeWillOpen(_ kind: Route.Kind, source: LYRouteSource) {}
    /// 默认不处理。
    func routeDidSettle(_ kind: Route.Kind?, source: LYRouteSource, result: LYOpenResult) {}
    /// 默认不处理。
    func routeDidDropPending(_ kind: Route.Kind, source: LYRouteSource, reason: LYPendingDropReason) {}
}
