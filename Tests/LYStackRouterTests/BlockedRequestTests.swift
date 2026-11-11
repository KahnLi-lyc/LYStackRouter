#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 外部请求在展示阶段被处理器或自定义容器挡住（`.blocked`）后，只在新的稳定事件到来时重试。
    @MainActor
    final class BlockedRequestTests: XCTestCase {
        private var blocker: Blocker!
        private var host: LYSingleStackHost!
        private var router: LYStackRouter<AppRoute>!

        override func setUp() async throws {
            blocker = Blocker()
            host = LYSingleStackHost(root: UIViewController())
            var environment = LYRouteEnvironment()
            environment.provide(Blocker.self, blocker)
            router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([BlockingModule.self]),
                environment: environment,
                allowsUnregistered: true
            )
        }

        override func tearDown() async throws {
            blocker.gate.open()
            router.tearDown()
        }

        // MARK: - Waiting

        func testBlockedRequestDoesNotReplayWithoutStabilization() async {
            blocker.blocked = ["a"]
            let result = await router.open(.chat("a"), source: .push)
            XCTAssertEqual(result, .deferred)
            await settle()
            XCTAssertEqual(blocker.calls["a"], 1, "没有新的稳定事件时不能自我重放")

            blocker.blocked = []
            router.navigationDidStabilize()
            await settle()
            XCTAssertEqual(blocker.calls["a"], 2, "稳定事件后执行一次")
            XCTAssertEqual(host.navigationController.viewControllers.count, 2)
        }

        func testNewerExternalRequestReplacesBlockedOne() async {
            blocker.blocked = ["a"]
            _ = await router.open(.chat("a"), source: .push)
            let newer = await router.open(.chat("b"), source: .deepLink)
            XCTAssertEqual(newer, .created)
            blocker.blocked = []
            router.navigationDidStabilize()
            await settle()
            XCTAssertEqual(blocker.calls["a"], 1, "被更新的外部请求取代后不再执行")
        }

        func testRequestArrivingDuringBlockedPreparationWins() async {
            let first = Task { await router.open(.slowChat("a"), source: .push) }
            await waitUntil { self.blocker.gate.waiting == 1 }
            let second = await router.open(.chat("b"), source: .deepLink)
            XCTAssertEqual(second, .deferred, "执行中到达的外部请求先等待")
            blocker.gate.open()
            let firstResult = await first.value
            XCTAssertEqual(firstResult, .deferred)
            await waitUntil { self.blocker.calls["b"] == 1 }
            await settle()
            XCTAssertEqual(blocker.calls["slow-a"], 1, "更早的受阻请求不能覆盖更新的等待请求")
        }

        func testSessionResetDropsBlockedRequest() async {
            blocker.blocked = ["a"]
            _ = await router.open(.chat("a"), source: .push)
            router.resetSession()
            blocker.blocked = []
            router.navigationDidStabilize()
            await settle()
            XCTAssertEqual(blocker.calls["a"], 1)
            XCTAssertEqual(host.navigationController.viewControllers.count, 1)
        }

        // MARK: - Helpers

        private func settle() async {
            for _ in 0 ..< 20 {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 2_000_000)
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

    /// 记录处理器调用次数，并模拟自定义容器挡住展示。
    @MainActor
    final class Blocker {
        var blocked: Set<String> = []
        var calls: [String: Int] = [:]
        let gate = Gate()
    }

    struct BlockingModule: LYRouteModule {
        static let moduleID = "blocking"
        let blocker: Blocker

        init(environment: LYRouteEnvironment) throws {
            blocker = try environment.require(Blocker.self)
        }

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            let blocker = blocker
            builder.page(.chat, policy: .init(allowsExternal: true)) { route, context in
                guard case let .chat(id) = route else { return }
                blocker.calls[id, default: 0] += 1
                if blocker.blocked.contains(id) {
                    context.fail(.blocked)
                } else {
                    context.show { TestPage(.chat(id)) }
                }
            }
            // 准备完成后被挡住，用来验证执行期间到达的更新请求不被覆盖。
            builder.page(.slowChat, policy: .init(allowsExternal: true)) { route, context in
                guard case let .slowChat(id) = route else { return }
                blocker.calls["slow-\(id)", default: 0] += 1
                context.prepare { context in
                    await blocker.gate.wait()
                    guard await context.isStillValid() else { return }
                    context.fail(.blocked)
                }
            }
        }
    }
#endif
