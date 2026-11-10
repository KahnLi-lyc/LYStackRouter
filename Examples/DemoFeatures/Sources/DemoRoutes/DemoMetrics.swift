import Foundation

/// 示例页面共用的观测数据：被路由器清理的页面数与最近一次导航结果，供界面和 UI 测试读取。
@MainActor
public final class DemoMetrics {
    // MARK: - Properties

    /// 数据变化通知。
    public static let didChange = Notification.Name("DemoMetricsDidChange")

    /// 被路由器移出并清理的页面数。
    public private(set) var cleanedPages = 0
    /// 最近一次导航结算，例如 `club: created`。
    public private(set) var lastEvent = "-"
    /// 最近几次结算，最新的在最后。
    public private(set) var recentEvents: [String] = []

    // MARK: - Initialization

    public init() {}

    // MARK: - Public

    /// 页面收到路由器清理通知时调用。
    public func pageWasRemoved() {
        cleanedPages += 1
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }

    /// 记录一次导航结算。
    public func record(_ event: String) {
        lastEvent = event
        recentEvents = Array((recentEvents + [event]).suffix(6))
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
