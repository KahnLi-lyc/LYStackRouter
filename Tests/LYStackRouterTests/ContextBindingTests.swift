#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 处理器上下文与确认回调的有效期：页面回调长期可用，单次执行的操作只作用于自己的执行。
    @MainActor
    final class ContextBindingTests: XCTestCase {
        private var probe: Probe!
        private var host: LYSingleStackHost!
        private var router: LYStackRouter<AppRoute>!

        override func setUp() async throws {
            probe = Probe()
            host = LYSingleStackHost(root: UIViewController())
            var environment = LYRouteEnvironment()
            environment.provide(Probe.self, probe)
            router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([ProbeModule.self]),
                environment: environment,
                allowsUnregistered: true
            )
        }

        override func tearDown() async throws {
            probe.gate.open()
            router.tearDown()
        }

        private var stack: [UIViewController] {
            host.navigationController.viewControllers
        }

        // MARK: - Page Callbacks

        func testContextOpenKeepsWorkingAfterSettlementAndSignIn() throws {
            XCTAssertEqual(router.request(.club("x")), .created)
            let context = try XCTUnwrap(probe.contexts.first)
            XCTAssertEqual(context.open(.profile("a")), .created, "原导航结算后，页面回调仍可发起导航")

            host.sessionID = "u1"
            router.sessionDidChange()
            XCTAssertEqual(context.open(.profile("b")), .created, "登录会更新代次，但已有页面的回调不能因此失效")

            router.tearDown()
            XCTAssertEqual(context.open(.profile("c")), .failed(.stopped))
        }

        // MARK: - Execution Binding

        func testStaleContextCannotChangeOrShowInLaterExecution() async throws {
            XCTAssertEqual(router.request(.club("x")), .created)
            let stale = try XCTUnwrap(probe.contexts.first)
            let opening = Task { await router.open(.slowChat("s")) }
            await waitUntil { self.probe.gate.waiting == 1 }

            stale.markPerformed()
            stale.show { TestPage(.profile("stale")) }
            XCTAssertEqual(stack.count, 2, "旧上下文不能在新执行中展示页面")

            probe.gate.open()
            let result = await opening.value
            XCTAssertEqual(result, .failed(.unavailable), "旧上下文不能改写新执行的结果")
        }

        // MARK: - Confirmation

        func testSettledConfirmationDoesNotRunAfterSessionReset() async {
            let presented = presentConfirmation()
            presented.onPresented()
            router.resetSession()
            presented.confirm()
            await settle()
            XCTAssertEqual(probe.confirmed, 0, "会话重置后，旧确认框的确认不能继续导航")
        }

        func testSettledConfirmationRunsOnceWithoutSessionChange() async {
            let presented = presentConfirmation()
            presented.onPresented()
            presented.confirm()
            presented.confirm()
            await settle()
            XCTAssertEqual(probe.confirmed, 1)
        }

        // MARK: - Helpers

        private func presentConfirmation() -> (onPresented: @MainActor () -> Void, confirm: @MainActor () -> Void) {
            var onPresented: (@MainActor () -> Void)?
            var confirm: (@MainActor () -> Void)?
            router.confirmationPresenter = { _, _, confirmAction, presented in
                confirm = confirmAction
                onPresented = presented
                return true
            }
            XCTAssertEqual(router.request(.room("r")), .awaitingConfirmation)
            return (onPresented ?? {}, confirm ?? {})
        }

        private func settle() async {
            for _ in 0 ..< 5 {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
        }

        private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 2) async {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(condition(), "等待条件超时")
        }
    }

    /// 记录处理器拿到的上下文与确认次数。
    @MainActor
    final class Probe {
        var contexts: [LYRouteContext<AppRoute>] = []
        var confirmed = 0
        let gate = Gate()
    }

    /// 只登记本组测试需要的路由；其他路由按非穷尽构建处理。
    struct ProbeModule: LYRouteModule {
        static let moduleID = "probe"
        let probe: Probe

        init(environment: LYRouteEnvironment) throws {
            probe = try environment.require(Probe.self)
        }

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            let probe = probe
            builder.page(.club) { route, context in
                probe.contexts.append(context)
                guard case let .club(id) = route else { return }
                context.show(identity: PageIdentity.club(id)) { TestPage(.club(id)) }
            }
            builder.page(.profile) { route, context in
                guard case let .profile(id) = route else { return }
                context.show { TestPage(.profile(id)) }
            }
            // 准备结束后不展示页面，结果保持页面路由的默认值 `.unavailable`。
            builder.page(.slowChat) { _, context in
                context.prepare { _ in await probe.gate.wait() }
            }
            builder.page(.room) { _, context in
                context.confirm(title: "t", message: nil, confirmTitle: "ok", cancelTitle: "no") { _ in
                    probe.confirmed += 1
                }
            }
        }
    }
#endif
