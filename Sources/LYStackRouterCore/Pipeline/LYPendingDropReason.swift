/// 等待中的外部请求被丢弃的原因。请求进入等待时已结算为 `.deferred`，丢弃时不再结算，只通知观察者。
public enum LYPendingDropReason: Sendable, Hashable {
    /// 被更新的外部请求取代：外部请求只保留最近一个。
    case superseded
    /// 执行前发现宿主会话已不是请求进入等待时的会话。
    case sessionChanged
    /// 调用 `resetSession()`、切换账号或退出登录，等待请求被清空。
    case sessionReset
    /// 请求携带的显式来源页面已释放、不在栈顶或不再属于宿主。
    case originUnavailable
    /// 路由器已停止。
    case stopped
}
