/// 路由的目标域，例如某个 Tab。具体含义由宿主解释。
///
/// 默认 `.current` 表示在当前导航域内打开。接入方用静态常量声明自己的域：
///
/// ```swift
/// extension LYRoutePlacement {
///     static let messages = LYRoutePlacement("messages")
/// }
/// ```
public struct LYRoutePlacement: Hashable, Sendable, CustomStringConvertible {
    /// 域标识。
    public let rawValue: String

    /// 创建一个目标域。
    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    /// 当前导航域。
    public static let current = LYRoutePlacement("current")

    /// 调试描述。
    public var description: String {
        rawValue
    }
}
