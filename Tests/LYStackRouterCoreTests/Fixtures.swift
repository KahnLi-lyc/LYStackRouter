import Foundation
@testable import LYStackRouterCore

/// 仿真接入方的路由枚举，覆盖常见的 URL 规则。
enum TestRoute: LYRoutable {
    case home
    case club(String)
    case room(String, entry: String)
    case chat(String, type: String)
    case profile(Int)
    case friends(String?)
    case web(String)
    case wallet

    enum Kind: CaseIterable {
        case home, club, room, chat, profile, friends, web, wallet
    }

    var kind: Kind {
        switch self {
        case .home: .home
        case .club: .club
        case .room: .room
        case .chat: .chat
        case .profile: .profile
        case .friends: .friends
        case .web: .web
        case .wallet: .wallet
        }
    }
}

typealias TestRegistry = LYRouteRegistry<TestRoute, Void>

let testConfiguration = LYURLConfiguration(schemes: ["myapp"], universalLinkHosts: ["app.example.com"])

/// 参考模块：按仿真规则登记 URL。room 的 entry 缺失或未知时回退为 notification；chat 只接受 team 与 peer。
@MainActor
func registerReferenceURLs(_ builder: inout TestRegistry.Builder) {
    builder.url("home", parse: { _ in .home }, print: { $0 == .home ? LYURLValues() : nil })
    builder.url("club/<clubID>", parse: { $0["clubID"].map(TestRoute.club) }, print: {
        if case let .club(id) = $0 { LYURLValues(path: ["clubID": id]) } else { nil }
    })
    builder.url("room/<roomID>", parse: { values in
        guard let id = values["roomID"] else { return nil }
        let known: Set = ["circle", "lounge", "notification"]
        let entry = values.query["entry"].flatMap { known.contains($0) ? $0 : nil } ?? "notification"
        return .room(id, entry: entry)
    }, print: {
        if case let .room(id, entry) = $0 { LYURLValues(path: ["roomID": id], query: ["entry": entry]) } else { nil }
    })
    builder.url("chat/<sessionID>", parse: { values in
        guard let id = values["sessionID"], let type = values.query["type"], ["team", "peer"].contains(type) else {
            return nil
        }
        return .chat(id, type: type)
    }, print: {
        if case let .chat(id, type) = $0 { LYURLValues(path: ["sessionID": id], query: ["type": type]) } else { nil }
    })
    builder.url("profile/<int:userID>", parse: { $0["userID"].flatMap(Int.init).map(TestRoute.profile) }, print: {
        if case let .profile(id) = $0 { LYURLValues(path: ["userID": String(id)]) } else { nil }
    })
    builder.url("friends", parse: { _ in .friends(nil) }, print: { $0 == .friends(nil) ? LYURLValues() : nil })
    builder.url("friends/<userID>", parse: { $0["userID"].map { .friends($0) } }, print: {
        if case let .friends(id?) = $0 { LYURLValues(path: ["userID": id]) } else { nil }
    })
    builder.url("web/<path:rest>", parse: { $0["rest"].map(TestRoute.web) }, print: {
        if case let .web(rest) = $0 { LYURLValues(path: ["rest": rest]) } else { nil }
    })
}

/// 为全部种类登记空处理器，得到一份穷尽的注册表。
@MainActor
func makeReferenceRegistry() throws -> TestRegistry {
    var builder = TestRegistry.Builder()
    builder.moduleID = "reference"
    for kind in TestRoute.Kind.allCases {
        builder.page(kind) { _, _ in }
    }
    registerReferenceURLs(&builder)
    return try builder.build(requireExhaustive: true)
}

func url(_ string: String) -> URL {
    URL(string: string)!
}
