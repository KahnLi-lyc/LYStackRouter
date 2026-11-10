import DemoRoutes
import LYStackRouterDiscovery
import UIKit

/// 消息模块：私信页。私信默认放进消息 Tab 的会话容器（由宿主的 `customShow` 钩子接管）。
@LYRouteModule
public struct MessagesRouteModule: LYRouteModule {
    // MARK: - Properties

    public static let moduleID = "messages"

    private let metrics: DemoMetrics

    // MARK: - Initialization

    public init(environment: LYRouteEnvironment) throws {
        metrics = try environment.require(DemoMetrics.self)
    }

    // MARK: - Public

    public func register(into builder: inout LYStackRouteRegistry<DemoRoute>.Builder) {
        builder.url("chat/<id>", parse: { $0["id"].map(DemoRoute.chat) }, print: { route in
            if case let .chat(id) = route { LYURLValues(path: ["id": id]) } else { nil }
        })
        let metrics = metrics
        builder.page(.chat, policy: .init(placement: .messages, allowsExternal: true, validate: { route in
            if case let .chat(id) = route { !id.isEmpty } else { false }
        })) { route, context in
            guard case let .chat(id) = route else { return }
            context.show(identity: DemoPageIdentity.chat(id)) { ChatPage(id: id, metrics: metrics, context: context) }
        }
    }
}

/// 私信页：打开俱乐部或房间时同样只发路由。
final class ChatPage: DemoPage {
    init(id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) {
        super.init(pageID: "chat.\(id)", title: "私信 \(id)", identity: .chat(id), metrics: metrics)
        open = { context.open($0) }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("查看俱乐部 B", id: "chat.open.club.B") { [weak self] in self?.open(.club("B")) }
        addButton("回到房间 r1", id: "chat.open.room.r1") { [weak self] in self?.open(.room("r1")) }
    }
}
