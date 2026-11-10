#if canImport(UIKit)
    import UIKit

    /// 页面可选遵循：提供实时的业务身份，用于“栈内已有就回到它”的复用判断。
    ///
    /// 身份每次从页面当前状态读取，例如“创建活动”页提交成功后变成“活动详情”，身份随之改变。
    /// 返回 nil 表示该页面不参与复用。未遵循协议的页面同样不参与复用。
    @MainActor
    public protocol LYPageIdentifiable: UIViewController {
        /// 当前业务身份。
        var routeIdentity: AnyHashable? { get }
    }

    /// 页面可选遵循：被路由器从导航栈移出后收到一次清理通知。
    ///
    /// 只有确实离开导航栈（且没有被重新挂到其他容器）的页面才会收到；交互返回取消时不会收到。
    /// 实现必须幂等：页面自身的 `didMove(toParent:)` 清理与这里可能都会执行。
    @MainActor
    public protocol LYRoutePageLifecycle: AnyObject {
        /// 页面已被路由器移出导航栈。
        func routerDidRemovePage()
    }
#endif
