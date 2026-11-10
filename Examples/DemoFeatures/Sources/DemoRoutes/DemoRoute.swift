import LYStackRouter

/// 示例 App 的全部路由。各业务模块只依赖这份定义，互相之间不 import。
public enum DemoRoute: LYRoutable {
    case club(String)
    case member(String)
    case slowClub(String)
    case room(String)
    case chat(String)
    case login
    case wallet

    public enum Kind: CaseIterable, Sendable {
        case club, member, slowClub, room, chat, login, wallet
    }

    public var kind: Kind {
        switch self {
        case .club: .club
        case .member: .member
        case .slowClub: .slowClub
        case .room: .room
        case .chat: .chat
        case .login: .login
        case .wallet: .wallet
        }
    }
}

/// 页面的业务身份，用于“栈内已有就回到它”。
public enum DemoPageIdentity: Hashable, Sendable {
    case club(String)
    case member(String)
    case room(String)
    case chat(String)
}

public extension LYRoutePlacement {
    /// 首页 Tab。
    static let home = LYRoutePlacement("home")
    /// 消息 Tab。
    static let messages = LYRoutePlacement("messages")
    /// 我的 Tab。
    static let me = LYRoutePlacement("me")
}
