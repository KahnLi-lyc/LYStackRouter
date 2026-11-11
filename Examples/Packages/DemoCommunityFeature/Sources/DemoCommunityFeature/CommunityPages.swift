import DemoRouteContract
import DemoUIKit
import LYStackRouter
import UIKit

/// 俱乐部页：演示循环复用、跨模块只发路由、异步准备与会话型页面入口。
final class ClubPage: DemoPage {
    // MARK: - Properties

    private let clubID: String
    private let entry: String?

    // MARK: - Initialization

    init(id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) {
        clubID = id
        entry = context.options.extras["entry"] as? String
        super.init(pageID: "club.\(id)", title: "俱乐部 \(id)", identity: .club(id), metrics: metrics)
        let client = context.makeClient(from: self)
        open = { route in Task { _ = await client.open(route) } }
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        if let entry { addNote("entry \(entry)", id: "club.entry") }
        addButton("成员 m1", id: "open.member.m1") { [weak self] in self?.open(.member("m1")) }
        addButton("私信群主（消息模块）", id: "open.chat.owner") { [weak self] in
            guard let self else { return }
            open(.chat("owner-\(clubID)"))
        }
        addButton("慢速俱乐部 S（准备 1.5 秒）", id: "open.slowClub.S") { [weak self] in self?.open(.slowClub("S")) }
        addButton("进入房间 r1", id: "open.room.r1") { [weak self] in self?.open(.room("r1")) }
        addButton("进入房间 r2", id: "open.room.r2") { [weak self] in self?.open(.room("r2")) }
    }
}

/// 成员页：从这里再打开俱乐部 A 会回到栈内已有的实例。
final class MemberPage: DemoPage {
    init(id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) {
        super.init(pageID: "member.\(id)", title: "成员 \(id)", identity: .member(id), metrics: metrics)
        let client = context.makeClient(from: self)
        open = { route in Task { _ = await client.open(route) } }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("俱乐部 A", id: "open.club.A") { [weak self] in self?.open(.club("A")) }
        addButton("俱乐部 B", id: "open.club.B") { [weak self] in self?.open(.club("B")) }
    }
}

/// 语音房页：同一时间只能在一个房间。
final class RoomPage: DemoPage {
    // MARK: - Properties

    let roomID: String
    var onLeave: (() -> Void)?
    var onMinimize: (() -> Void)?
    var sessionDescription = ""
    private var minimized = false
    private var client: LYRouteClient<DemoRoute>?

    // MARK: - Initialization

    init(id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) {
        roomID = id
        super.init(pageID: "room.\(id)", title: "房间 \(id)", identity: .room(id), metrics: metrics)
        let client = context.makeClient(from: self)
        self.client = client
        open = { route in Task { _ = await client.open(route) } }
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        addNote(sessionDescription, id: "room.session")
        addButton("最小化房间", id: "room.minimize") { [weak self] in
            guard let self, let client, !minimized else { return }
            minimized = true
            Task {
                let result = await client.dismiss(animated: false)
                if result.isSuccess {
                    onMinimize?()
                } else {
                    minimized = false
                }
            }
        }
        addNote("房间进行中。切到其他 Tab 后再次打开同一房间，会切回这里。")
        addButton("进入房间 r2", id: "open.room.r2") { [weak self] in self?.open(.room("r2")) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent, !minimized { onLeave?() }
    }
}

/// 当前所在的语音房。由社群模块实例持有，因此每个路由器各有一份。
@MainActor
final class RoomSession {
    // MARK: - Properties

    private(set) weak var current: RoomPage?
    private(set) var roomID: String?
    private var sessionCount = 0

    // MARK: - Internal

    /// 创建并记录新的房间页。
    func enter(_ id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) -> RoomPage {
        if roomID != id { sessionCount += 1 }
        roomID = id
        let page = RoomPage(id: id, metrics: metrics, context: context)
        page.sessionDescription = "session \(id) · started \(sessionCount)"
        page.onMinimize = { [weak self] in self?.current = nil }
        page.onLeave = { [weak self, weak page] in
            if self?.current === page {
                self?.current = nil
                self?.roomID = nil
            }
        }
        current = page
        return page
    }

    /// 离开当前房间：把房间页从它所在的导航栈移除（可能在另一个 Tab）。
    func leaveCurrent() {
        roomID = nil
        guard let page = current else { return }
        current = nil
        if let navigation = page.navigationController {
            navigation.setViewControllers(navigation.viewControllers.filter { $0 !== page }, animated: false)
        }
        page.routerDidRemovePage()
    }
}

/// 模态流程内使用来源限定客户端继续导航，关闭时只结束本流程。
final class FlowPage: DemoPage {
    private var client: LYRouteClient<DemoRoute>?

    init(metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) {
        super.init(pageID: "flow", title: "模态流程", identity: nil, metrics: metrics)
        client = context.makeClient(from: self)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("流程内打开成员", id: "flow.member") { [weak self] in
            guard let client = self?.client else { return }
            Task { _ = await client.open(.member("modal"), options: LYOpenOptions(animated: false, extras: ["entry": "flow"])) }
        }
        addButton("关闭流程", id: "flow.close") { [weak self] in
            guard let client = self?.client else { return }
            Task { _ = await client.dismiss() }
        }
    }
}
