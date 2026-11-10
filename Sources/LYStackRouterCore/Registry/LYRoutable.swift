/// 接入方的路由类型需要遵循的协议，通常是一个枚举。
///
/// `Kind` 是路由的“种类”，每个 case 对应一种页面或动作，用于注册与穷尽检查。
/// 建议 `kind` 用 `switch` 实现：新增路由 case 时编译器会强制补齐。
///
/// ```swift
/// enum AppRoute: LYRoutable {
///     case club(String), chat(String)
///     enum Kind: CaseIterable { case club, chat }
///     var kind: Kind {
///         switch self {
///         case .club: .club
///         case .chat: .chat
///         }
///     }
/// }
/// ```
public protocol LYRoutable: Hashable, Sendable {
    /// 路由种类，必须列出全部取值。
    associatedtype Kind: Hashable, CaseIterable, Sendable

    /// 当前路由所属的种类。
    var kind: Kind { get }
}
