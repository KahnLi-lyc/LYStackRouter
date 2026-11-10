/// 一次导航请求的结算结果。每次执行只结算一次。
public enum LYOpenResult: Hashable, Sendable {
    /// 创建了新页面。
    case created
    /// 回到了栈内已有的同身份页面。
    case reused
    /// 目标页面已在栈顶，无需操作。
    case alreadyVisible
    /// 动作路由已执行，没有改变导航栈。
    case performed
    /// 已展示确认框，等待用户确认；确认后的后续导航是另一次执行。
    case awaitingConfirmation
    /// 外部请求因宿主暂时受阻而进入等待，尚未打开。
    case deferred
    /// 用户请求因导航处理中被忽略。
    case ignored
    /// 失败及原因。
    case failed(LYRouteFailure)

    /// 是否已经完成展示或动作。
    public var isSuccess: Bool {
        switch self {
        case .created, .reused, .alreadyVisible, .performed: true
        case .awaitingConfirmation, .deferred, .ignored, .failed: false
        }
    }
}
