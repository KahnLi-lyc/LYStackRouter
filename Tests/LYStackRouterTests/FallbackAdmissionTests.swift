#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 兜底展示前的准入：禁用或未注册的路由走兜底时，仍要先过外部白名单、参数校验与拦截器。
    @MainActor
    final class FallbackAdmissionTests: XCTestCase {
        private var host: LYSingleStackHost!
        private var router: LYStackRouter<AppRoute>!
        private var fallbackCalls: [(AppRoute.Kind, LYRouteFallbackReason)] = []
        private var signedIn = false

        override func setUp() async throws {
            host = LYSingleStackHost(root: UIViewController())
            router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([DegradedModule.self]),
                interceptors: [.session(isActive: { [weak self] in self?.signedIn ?? false })],
                fallback: LYRouteFallback { [weak self] route, reason, context in
                    self?.fallbackCalls.append((route.kind, reason))
                    context.show { TestPage(nil) }
                },
                allowsUnregistered: true
            )
        }

        override func tearDown() async throws {
            router.tearDown()
        }

        private var stackCount: Int {
            host.navigationController.viewControllers.count
        }

        // MARK: - Static Disabled

        func testDisabledFallbackRequiresExternalAllowance() async {
            let result = await router.open(.profile("a"), source: .deepLink)
            XCTAssertEqual(result, .failed(.notExternal))
            XCTAssertTrue(fallbackCalls.isEmpty, "不允许外部来源的路由，禁用后也不能被深链打开兜底")
            XCTAssertEqual(stackCount, 1)
        }

        func testDisabledFallbackRequiresValidParameters() {
            XCTAssertEqual(router.request(.profile("")), .failed(.invalidParameter))
            XCTAssertTrue(fallbackCalls.isEmpty)
            XCTAssertEqual(stackCount, 1)
        }

        func testDisabledFallbackWaitsForSessionThenRunsOnce() async {
            let deferred = await router.open(.settings, source: .push)
            XCTAssertEqual(deferred, .deferred)
            XCTAssertTrue(fallbackCalls.isEmpty, "会话未就绪时兜底不能执行")

            signedIn = true
            host.sessionID = "u1"
            router.sessionDidChange()
            await waitUntil { self.fallbackCalls.count == 1 }
            XCTAssertEqual(fallbackCalls.map(\.1), [.unavailable])
            XCTAssertEqual(stackCount, 2)
        }

        func testDisabledFallbackRunsOnceWhenAllPoliciesPass() {
            XCTAssertEqual(router.request(.profile("a")), .created)
            XCTAssertEqual(fallbackCalls.map(\.1), [.unavailable])
        }

        // MARK: - Remote Rewrite

        func testRewriteDisabledKindStillChecksPolicies() async {
            router.rewrite = LYRouteRewrite(disabledKinds: ["club"])
            let external = await router.open(.club("x"), source: .deepLink)
            XCTAssertEqual(external, .failed(.notExternal))
            XCTAssertEqual(router.request(.club("")), .failed(.invalidParameter))
            XCTAssertTrue(fallbackCalls.isEmpty)
            XCTAssertEqual(router.request(.club("x")), .created)
            XCTAssertEqual(fallbackCalls.map(\.1), [.unavailable])
        }

        // MARK: - Placeholder and Unregistered

        func testPlaceholderFallbackKeepsFullAdmission() async {
            let external = await router.open(.room("r"), source: .deepLink)
            XCTAssertEqual(external, .failed(.notExternal))
            XCTAssertEqual(router.request(.room("r")), .created)
            XCTAssertEqual(fallbackCalls.map(\.1), [.placeholder])
        }

        func testUnregisteredRouteRejectsExternalRequestsEvenWithFallback() async {
            let external = await router.open(.chat("c"), source: .deepLink)
            XCTAssertEqual(external, .failed(.unregistered), "未注册路由没有策略，不能推断为允许外部打开")
            XCTAssertTrue(fallbackCalls.isEmpty)
            XCTAssertEqual(router.request(.chat("c")), .created, "本地请求仍可使用模块 Demo 的兜底")
            XCTAssertEqual(fallbackCalls.map(\.1), [.unregistered])
        }

        // MARK: - Helpers

        private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 2) async {
            let deadline = Date().addingTimeInterval(timeout)
            while !condition(), Date() < deadline {
                await Task.yield()
                try? await Task.sleep(nanoseconds: 5_000_000)
            }
            XCTAssertTrue(condition(), "等待条件超时")
        }
    }

    /// 处于降级状态的路由：处理器不应被调用，请求只会进入兜底。
    struct DegradedModule: LYRouteModule {
        static let moduleID = "degraded"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            builder.page(.profile, policy: .init(status: .disabled, validate: { route in
                if case let .profile(id) = route { !id.isEmpty } else { false }
            })) { _, _ in XCTFail("禁用路由的处理器不应被调用") }
            builder.page(.settings, policy: .init(status: .disabled, allowsExternal: true, requiresSession: true)) { _, _ in
                XCTFail("禁用路由的处理器不应被调用")
            }
            builder.page(.club, policy: .init(validate: { route in
                if case let .club(id) = route { !id.isEmpty } else { false }
            })) { _, _ in XCTFail("被远程配置禁用的路由不应调用处理器") }
            builder.page(.room, policy: .init(status: .placeholder)) { _, _ in
                XCTFail("占位路由在有兜底时不应调用处理器")
            }
        }
    }
#endif
