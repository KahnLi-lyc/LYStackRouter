import DemoRoutes
import LYStackRouter
import UIKit

/// 俱乐部页：演示循环复用、跨模块只发路由、异步准备与会话型页面入口。
final class ClubPage: DemoPage {
    // MARK: - Properties

    private let clubID: String

    // MARK: - Initialization

    init(id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) {
        clubID = id
        super.init(pageID: "club.\(id)", title: "俱乐部 \(id)", identity: .club(id), metrics: metrics)
        open = { context.open($0) }
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
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
        open = { context.open($0) }
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

    // MARK: - Initialization

    init(id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) {
        roomID = id
        super.init(pageID: "room.\(id)", title: "房间 \(id)", identity: .room(id), metrics: metrics)
        open = { context.open($0) }
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        addNote("房间进行中。切到其他 Tab 后再次打开同一房间，会切回这里。")
        addButton("进入房间 r2", id: "open.room.r2") { [weak self] in self?.open(.room("r2")) }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if isMovingFromParent { onLeave?() }
    }
}

/// 当前所在的语音房。由社群模块实例持有，因此每个路由器各有一份。
@MainActor
final class RoomSession {
    // MARK: - Properties

    private(set) weak var current: RoomPage?

    // MARK: - Internal

    /// 创建并记录新的房间页。
    func enter(_ id: String, metrics: DemoMetrics, context: LYRouteContext<DemoRoute>) -> RoomPage {
        let page = RoomPage(id: id, metrics: metrics, context: context)
        page.onLeave = { [weak self, weak page] in
            if self?.current === page { self?.current = nil }
        }
        current = page
        return page
    }

    /// 离开当前房间：把房间页从它所在的导航栈移除（可能在另一个 Tab）。
    func leaveCurrent() {
        guard let page = current else { return }
        current = nil
        if let navigation = page.navigationController {
            navigation.setViewControllers(navigation.viewControllers.filter { $0 !== page }, animated: false)
        }
        page.routerDidRemovePage()
    }
}
