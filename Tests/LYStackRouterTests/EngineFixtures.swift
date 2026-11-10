#if canImport(UIKit)
    import UIKit
    @testable import LYStackRouter

    enum AppRoute: LYRoutable {
        case club(String)
        case chat(String)
        case profile(String)
        case settings
        case wallet
        case slowChat(String)
        case room(String)

        enum Kind: CaseIterable {
            case club, chat, profile, settings, wallet, slowChat, room
        }

        var kind: Kind {
            switch self {
            case .club: .club
            case .chat: .chat
            case .profile: .profile
            case .settings: .settings
            case .wallet: .wallet
            case .slowChat: .slowChat
            case .room: .room
            }
        }
    }

    enum PageIdentity: Hashable {
        case club(String), chat(String), profile(String), room(String)
    }

    /// 可复用、可观察清理次数的测试页面。
    final class TestPage: UIViewController, LYPageIdentifiable, LYRoutePageLifecycle {
        var identity: PageIdentity?
        private(set) var removedCount = 0

        init(_ identity: PageIdentity?, title: String = "") {
            self.identity = identity
            super.init(nibName: nil, bundle: nil)
            self.title = title
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError()
        }

        var routeIdentity: AnyHashable? {
            identity.map(AnyHashable.init)
        }

        func routerDidRemovePage() {
            removedCount += 1
        }
    }

    /// 控制异步准备何时完成的门闩。
    @MainActor
    final class Gate {
        private var continuations: [CheckedContinuation<Void, Never>] = []
        private(set) var waiting = 0

        func wait() async {
            waiting += 1
            await withCheckedContinuation { continuations.append($0) }
        }

        func open() {
            let pending = continuations
            continuations.removeAll()
            pending.forEach { $0.resume() }
        }
    }

    struct Dependencies {
        let gate: Gate
        var created: (TestPage) -> Void = { _ in }
    }

    struct CommunityModule: LYRouteModule {
        static let moduleID = "community"
        let dependencies: Dependencies

        init(environment: LYRouteEnvironment) throws {
            dependencies = try environment.require(Dependencies.self)
        }

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            builder.url("club/<clubID>", parse: { $0["clubID"].map(AppRoute.club) }, print: { route in
                if case let .club(id) = route { LYURLValues(path: ["clubID": id]) } else { nil }
            })
            builder.url("profile/<userID>", parse: { $0["userID"].map(AppRoute.profile) }, print: { route in
                if case let .profile(id) = route { LYURLValues(path: ["userID": id]) } else { nil }
            })
            builder.page(.club, policy: .init(allowsExternal: true, validate: { route in
                if case let .club(id) = route { !id.isEmpty } else { false }
            })) { route, context in
                guard case let .club(id) = route else { return }
                context.show(identity: PageIdentity.club(id)) { TestPage(.club(id), title: "club \(id)") }
            }
            builder.page(.profile) { route, context in
                guard case let .profile(id) = route else { return }
                context.show(identity: PageIdentity.profile(id)) { TestPage(.profile(id)) }
            }
            builder.page(.settings, policy: .init(placement: LYRoutePlacement("me"), allowsExternal: true)) { _, context in
                context.show { TestPage(nil, title: "settings") }
            }
            builder.action(.wallet, policy: .init(allowsExternal: true, requiresSession: true)) { _, context in
                context.markPerformed()
            }
        }
    }

    struct ChatModule: LYRouteModule {
        static let moduleID = "chat"
        let gate: Gate

        init(environment: LYRouteEnvironment) throws {
            gate = try environment.require(Dependencies.self).gate
        }

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            builder.page(.chat, policy: .init(placement: LYRoutePlacement("messages"), allowsExternal: true)) { route, context in
                guard case let .chat(id) = route else { return }
                context.show(identity: PageIdentity.chat(id)) { TestPage(.chat(id)) }
            }
            let gate = gate
            builder.page(.slowChat, policy: .init(allowsExternal: true)) { route, context in
                guard case let .slowChat(id) = route else { return }
                context.prepare { context in
                    await gate.wait()
                    guard await context.isStillValid() else { return }
                    context.show(identity: PageIdentity.chat(id)) { TestPage(.chat(id)) }
                }
            }
            builder.page(.room) { route, context in
                guard case let .room(id) = route else { return }
                if context.revealExisting(where: { ($0 as? TestPage)?.identity == .room(id) }) { return }
                context.show(identity: PageIdentity.room(id)) { TestPage(.room(id)) }
            }
        }
    }

    @MainActor
    final class RecordingObserver: LYRouteObserver {
        typealias Route = AppRoute
        var willOpen: [AppRoute.Kind] = []
        var settled: [(AppRoute.Kind?, LYOpenResult)] = []

        func routeWillOpen(_ kind: AppRoute.Kind, source: LYRouteSource) {
            willOpen.append(kind)
        }

        func routeDidSettle(_ kind: AppRoute.Kind?, source: LYRouteSource, result: LYOpenResult) {
            settled.append((kind, result))
        }
    }

    @MainActor
    func makeEnvironment(gate: Gate = Gate()) -> LYRouteEnvironment {
        var environment = LYRouteEnvironment()
        environment.provide(Dependencies.self, Dependencies(gate: gate))
        return environment
    }

    @MainActor
    func makeTabHost() -> LYTabBarHost {
        let tabs = UITabBarController()
        tabs.viewControllers = [
            UINavigationController(rootViewController: TestPage(nil, title: "home")),
            UINavigationController(rootViewController: TestPage(nil, title: "messages")),
            UINavigationController(rootViewController: TestPage(nil, title: "me"))
        ]
        return LYTabBarHost(
            tabBarController: tabs,
            placements: [LYRoutePlacement("home"): 0, LYRoutePlacement("messages"): 1, LYRoutePlacement("me"): 2]
        )
    }
#endif
