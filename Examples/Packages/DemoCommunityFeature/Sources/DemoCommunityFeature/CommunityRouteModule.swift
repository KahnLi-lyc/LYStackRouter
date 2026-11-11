import DemoRouteContract
import DemoUIKit
import LYStackRouterDiscovery
import UIKit

/// 社群模块：俱乐部、成员、慢速俱乐部与语音房。
///
/// 只依赖 `DemoRoute`；打开私信等其他模块的页面时只发路由，不引用对方的类型。
@LYRouteModule
public struct CommunityRouteModule: LYRouteModule {
    // MARK: - Properties

    public static let moduleID = "community"

    private let metrics: DemoMetrics
    private let rooms = RoomSession()

    // MARK: - Initialization

    public init(environment: LYRouteEnvironment) throws {
        metrics = try environment.require(DemoMetrics.self)
    }

    // MARK: - Public

    public func register(into builder: inout LYStackRouteRegistry<DemoRoute>.Builder) {
        registerURLs(into: &builder)
        let metrics = metrics
        let rooms = rooms

        builder.page(.club, policy: .init(allowsExternal: true, validate: Self.hasID)) { route, context in
            guard case let .club(id) = route else { return }
            context.show(identity: DemoPageIdentity.club(id)) { ClubPage(id: id, metrics: metrics, context: context) }
        }
        builder.page(.member, policy: .init(allowsExternal: true, validate: Self.hasID)) { route, context in
            guard case let .member(id) = route else { return }
            context.show(identity: DemoPageIdentity.member(id)) { MemberPage(id: id, metrics: metrics, context: context) }
        }
        // 异步准备：等待期间点返回会抢占本次导航，迟到的结果不会再展示页面。
        builder.page(.slowClub, policy: .init(validate: Self.hasID)) { route, context in
            guard case let .slowClub(id) = route else { return }
            context.prepare { context in
                try await Task.sleep(nanoseconds: 1_500_000_000)
                guard await context.isStillValid() else { return }
                context.show(identity: DemoPageIdentity.club(id)) { ClubPage(id: id, metrics: metrics, context: context) }
            }
        }
        builder.page(.flow) { _, context in
            let page = FlowPage(metrics: metrics, context: context)
            // 全屏弹出的导航流程：流程内页面以自身为来源继续在弹出栈中导航。
            let flow = UINavigationController(rootViewController: page)
            flow.modalPresentationStyle = .fullScreen
            context.present(flow)
        }
        // 会话型页面：任何 Tab 中已有同一房间就切过去；已在别的房间时先确认离开。
        builder.page(.room, policy: .init(validate: Self.hasID)) { route, context in
            guard case let .room(id) = route else { return }
            if context.revealExisting(where: { ($0 as? RoomPage)?.roomID == id }) { return }
            guard let currentID = rooms.roomID, currentID != id else {
                context.show(identity: DemoPageIdentity.room(id)) { rooms.enter(id, metrics: metrics, context: context) }
                return
            }
            context.confirm(
                title: "离开房间 \(currentID)？",
                message: "进入房间 \(id) 前需要先离开当前房间",
                confirmTitle: "离开并进入",
                cancelTitle: "留下"
            ) { context in
                rooms.leaveCurrent()
                context.show(identity: DemoPageIdentity.room(id)) { rooms.enter(id, metrics: metrics, context: context) }
            }
        }
    }

    // MARK: - Private

    private static func hasID(_ route: DemoRoute) -> Bool {
        switch route {
        case let .club(id), let .member(id), let .slowClub(id), let .room(id): !id.isEmpty
        default: false
        }
    }

    private func registerURLs(into builder: inout LYStackRouteRegistry<DemoRoute>.Builder) {
        builder.url("club/<id>", parse: { $0["id"].map(DemoRoute.club) }, print: { route in
            if case let .club(id) = route { LYURLValues(path: ["id": id]) } else { nil }
        })
        builder.url("member/<id>", parse: { $0["id"].map(DemoRoute.member) }, print: { route in
            if case let .member(id) = route { LYURLValues(path: ["id": id]) } else { nil }
        })
    }
}
