#if canImport(UIKit)
    import UIKit

    /// 能主动上报导航栈 `didShow` 事件的宿主。路由器 `attach` 时自动接上回调。
    ///
    /// 库内的 `LYSingleStackHost` 与 `LYTabBarHost` 都遵循它；自定义宿主也可以遵循，省去手动调用。
    @MainActor
    public protocol LYNavigationEventSource: AnyObject {
        /// 导航栈完成展示（包括交互返回被取消后恢复原栈）时回调。
        var onNavigationDidShow: ((UINavigationController) -> Void)? { get set }
    }
#endif
