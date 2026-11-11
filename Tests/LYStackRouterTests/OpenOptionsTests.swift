#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 请求选项与静态准入规则的回归验证。
    @MainActor
    final class OpenOptionsTests: XCTestCase {
        func testExplicitNonanimatedShowAlsoDisablesReuseAnimation() throws {
            let navigation = AnimationRecordingNavigationController()
            let first = TestPage(.club("first"))
            navigation.setViewControllers([UIViewController(), first, TestPage(.club("second"))], animated: false)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.addSubview(navigation.view)
            let host = LYSingleStackHost(navigationController: navigation)
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([NonanimatedModule.self]),
                allowsUnregistered: true
            )
            defer { router.tearDown() }

            XCTAssertEqual(router.request(.club("first")), .reused)
            XCTAssertTrue(navigation.topViewController === first)
            XCTAssertEqual(navigation.lastSetAnimated, false)
            withExtendedLifetime(window) {}
        }

        /// `context.replaceStack` 默认跟随请求的动画选项，显式参数优先。
        func testReplaceStackFollowsRequestAnimationAndExplicitOverride() throws {
            let navigation = AnimationRecordingNavigationController()
            navigation.setViewControllers([UIViewController(), UIViewController()], animated: false)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.addSubview(navigation.view)
            let host = LYSingleStackHost(navigationController: navigation)
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([ReplaceModule.self]),
                allowsUnregistered: true
            )
            defer { router.tearDown() }

            XCTAssertEqual(router.request(.club("default"), options: .init(animated: false)), .created)
            XCTAssertEqual(navigation.lastSetAnimated, false)
            XCTAssertEqual(router.request(.club("override"), options: .init(animated: false)), .created)
            XCTAssertEqual(navigation.lastSetAnimated, true)
            withExtendedLifetime(window) {}
        }

        /// 静态检查与实际提交逐项一致：`canOpen` 为 false 时提交以同一失败结束；为 true 时提交不会因静态规则失败。
        func testStaticChecksAgreeWithSubmissionAcrossSourcesAndFallbacks() async throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeOptionsRouter(host: host, probe: probe, fallback: .placeholder)
            let staticFailures: Set<LYOpenResult> = [
                .failed(.unregistered), .failed(.unavailable), .failed(.notExternal), .failed(.invalidParameter), .failed(.stopped)
            ]
            let cases: [(AppRoute, LYRouteSource, Bool, LYOpenResult?)] = [
                (.club("1"), .user, true, .performed),
                (.club("1"), .push, true, .performed),
                (.club(""), .user, false, .failed(.invalidParameter)),
                (.profile("p"), .user, true, .performed),
                (.profile("p"), .deepLink, false, .failed(.notExternal)),
                (.room("r"), .user, true, nil),
                (.room("r"), .push, false, .failed(.unregistered)),
                (.settings, .user, true, nil),
                (.wallet, .user, true, nil)
            ]
            for (route, source, expected, result) in cases {
                XCTAssertEqual(router.canOpen(route, source: source), expected, "\(route) \(source)")
                let opened = await router.open(route, source: source, options: .init(animated: false))
                if let result {
                    XCTAssertEqual(opened, result, "\(route) \(source)")
                } else {
                    XCTAssertFalse(staticFailures.contains(opened), "\(route) \(source) 不应因静态规则失败：\(opened)")
                }
            }
            router.tearDown()
            XCTAssertFalse(router.canOpen(.club("1")))
            let stopped = await router.open(.club("1"))
            XCTAssertEqual(stopped, .failed(.stopped))
        }

        func testOpenPassesExtrasAnimationAndWeakOriginToHandler() async throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeOptionsRouter(host: host, probe: probe)
            defer { router.tearDown() }
            let origin = try XCTUnwrap(host.navigationController.topViewController)
            let result = await router.open(.club("one"), options: .init(animated: false, from: origin, extras: ["campaign": "launch", "attempt": 2]))

            XCTAssertEqual(result, .performed)
            XCTAssertEqual(probe.options?.animated, false)
            XCTAssertTrue(probe.options?.from === origin)
            XCTAssertEqual(probe.options?.extras["campaign"] as? String, "launch")
            XCTAssertEqual(probe.options?.extras["attempt"] as? Int, 2)
        }

        func testCustomShowReceivesOptionsAndConstructsPageOnce() async throws {
            let probe = ShowProbe()
            let host = OptionsCustomHost()
            let router = try makeShowRouter(host: host, probe: probe)
            defer { router.tearDown() }
            let origin = try XCTUnwrap(host.activeNavigationController?.topViewController)

            let result = await router.open(.club("one"), options: .init(animated: false, from: origin, extras: ["campaign": "show"]))
            XCTAssertEqual(result, .created)
            XCTAssertEqual(host.options?.animated, false)
            XCTAssertTrue(host.options?.from === origin)
            XCTAssertEqual(host.options?.extras["campaign"] as? String, "show")
            XCTAssertEqual(probe.createdCount, 1)
        }

        func testLegacyCustomShowStillHandlesRequestsWithOptions() async throws {
            let probe = ShowProbe()
            let host = LegacyCustomHost()
            let router = try makeShowRouter(host: host, probe: probe)
            defer { router.tearDown() }

            let result = await router.open(.club("one"), options: .init(animated: false, extras: ["campaign": "legacy"]))
            XCTAssertEqual(result, .created)
            XCTAssertEqual(host.calls, 1)
            XCTAssertNotNil(host.displayedPage)
            XCTAssertEqual(probe.createdCount, 1)
        }

        func testExplicitShowAnimationOverridesRequestInBothDirections() async throws {
            let probe = ShowProbe()
            let host = OptionsCustomHost()
            let router = try makeShowRouter(host: host, probe: probe)
            defer { router.tearDown() }

            let nonanimated = await router.open(.profile("one"), options: .init(animated: true))
            XCTAssertEqual(nonanimated, .created)
            XCTAssertEqual(host.options?.animated, false)
            let animated = await router.open(.room("one"), options: .init(animated: false))
            XCTAssertEqual(animated, .created)
            XCTAssertEqual(host.options?.animated, true)
        }

        func testPrepareRetainsOptionsBeforeShowing() async throws {
            let probe = ShowProbe()
            let host = OptionsCustomHost()
            let router = try makeShowRouter(host: host, probe: probe)
            defer {
                probe.gate.open()
                router.tearDown()
            }
            let origin = try XCTUnwrap(host.activeNavigationController?.topViewController)
            let opening = Task { await router.open(.slowChat("one"), options: .init(animated: false, from: origin, extras: ["campaign": "prepare"])) }
            for _ in 0 ..< 50 where probe.gate.waiting == 0 {
                await Task.yield()
            }
            XCTAssertEqual(probe.gate.waiting, 1)
            probe.gate.open()

            let result = await opening.value
            XCTAssertEqual(result, .created)
            XCTAssertEqual(probe.preparedOptions?.animated, false)
            XCTAssertTrue(probe.preparedOptions?.from === origin)
            XCTAssertEqual(probe.preparedOptions?.extras["campaign"] as? String, "prepare")
            XCTAssertEqual(host.options?.animated, false)
            XCTAssertEqual(probe.createdCount, 1)
        }

        func testStaticChecksDoNotInvokeInterceptorsHandlersOrObservers() throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            host.isReady = false
            let observer = RecordingObserver()
            let router = try makeOptionsRouter(host: host, probe: probe, observers: [observer])
            defer { router.tearDown() }

            XCTAssertTrue(router.canOpen(.club("one")))
            XCTAssertTrue(try router.canOpenURL(XCTUnwrap(URL(string: "test://club/one"))))
            XCTAssertFalse(router.canOpen(.club("")))
            XCTAssertFalse(router.canOpen(.profile("one"), source: .push))
            XCTAssertFalse(try router.canOpenURL(XCTUnwrap(URL(string: "other://club/one"))))
            XCTAssertEqual(probe.handlerCalls, 0)
            XCTAssertEqual(probe.interceptorCalls, 0)
            XCTAssertTrue(observer.willOpen.isEmpty)
            XCTAssertTrue(observer.settled.isEmpty)
        }

        func testStaticFailureMatchesSubmissionBeforeAnySideEffects() async throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeOptionsRouter(host: host, probe: probe)
            defer { router.tearDown() }
            let cases: [(AppRoute, LYRouteSource, LYRouteFailure)] = [
                (.club(""), .user, .invalidParameter),
                (.profile("one"), .push, .notExternal),
                (.room("one"), .user, .unregistered),
                (.settings, .user, .unavailable)
            ]
            for (route, source, failure) in cases {
                XCTAssertFalse(router.canOpen(route, source: source))
                let result = await router.open(route, source: source)
                XCTAssertEqual(result, .failed(failure))
            }
            XCTAssertEqual(probe.handlerCalls, 0)
            XCTAssertEqual(probe.interceptorCalls, 0)
            router.tearDown()
            XCTAssertFalse(router.canOpen(.club("one")))
            XCTAssertFalse(try router.canOpenURL(XCTUnwrap(URL(string: "test://club/one"))))
        }

        func testStaticChecksIncludeLegalFallbackWithoutRunningIt() throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            var fallbackCalls = 0
            let router = try makeOptionsRouter(host: host, probe: probe, fallback: LYRouteFallback { _, _, context in
                fallbackCalls += 1
                context.markPerformed()
            })
            defer { router.tearDown() }

            XCTAssertTrue(router.canOpen(.settings))
            XCTAssertTrue(router.canOpen(.room("one")))
            XCTAssertFalse(router.canOpen(.room("one"), source: .push))
            XCTAssertEqual(fallbackCalls, 0)
            XCTAssertEqual(router.request(.settings), .performed)
            XCTAssertEqual(fallbackCalls, 1)
        }

        func testDeferredRequestRetainsExtrasAndAnimation() async throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            host.isReady = false
            let router = try makeOptionsRouter(host: host, probe: probe)
            defer { router.tearDown() }
            let deferred = await router.open(.club("one"), source: .push, options: .init(animated: false, extras: ["source": "notification"]))
            XCTAssertEqual(deferred, .deferred)
            XCTAssertEqual(probe.handlerCalls, 0)

            host.isReady = true
            router.navigationDidStabilize()
            for _ in 0 ..< 50 where probe.handlerCalls == 0 {
                await Task.yield()
            }
            XCTAssertEqual(probe.handlerCalls, 1)
            XCTAssertEqual(probe.options?.animated, false)
            XCTAssertEqual(probe.options?.extras["source"] as? String, "notification")
        }

        func testRedirectRetainsOptions() async throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeOptionsRouter(host: host, probe: probe)
            defer { router.tearDown() }
            let result = await router.open(.club("redirect"), options: .init(animated: false, extras: ["origin": "button"]))
            XCTAssertEqual(result, .performed)
            XCTAssertEqual(probe.route, .profile("redirected"))
            XCTAssertEqual(probe.options?.animated, false)
            XCTAssertEqual(probe.options?.extras["origin"] as? String, "button")
        }

        func testReleasedExplicitOriginCannotRetargetToCurrentTop() throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            let router = try makeOptionsRouter(host: host, probe: probe)
            defer { router.tearDown() }
            var origin: UIViewController? = UIViewController()
            weak var weakOrigin: UIViewController?
            weakOrigin = origin
            let options = LYOpenOptions(from: origin)
            origin = nil

            XCTAssertNil(weakOrigin)
            XCTAssertNil(options.from)
            XCTAssertEqual(router.request(.club("one"), options: options), .ignored, "失效来源的用户请求按迟到点击忽略")
            XCTAssertEqual(probe.handlerCalls, 0)
        }

        func testDisabledFallbackDoesNotWaitForBlockedOriginalTargetDomain() async throws {
            let current = UINavigationController(rootViewController: UIViewController())
            let blocked = BlockedNavigationController(rootViewController: UIViewController())
            blocked.blocker = UIViewController()
            let tabs = UITabBarController()
            tabs.viewControllers = [current, blocked]
            let host = LYTabBarHost(tabBarController: tabs, placements: [LYRoutePlacement("me"): 1])
            host.isReady = false
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([DisabledPlacedModule.self]),
                fallback: .placeholder,
                allowsUnregistered: true
            )
            defer { router.tearDown() }
            let deferred = await router.open(.settings, source: .push)
            XCTAssertEqual(deferred, .deferred)

            host.isReady = true
            router.navigationDidStabilize()
            for _ in 0 ..< 50 where current.viewControllers.count == 1 {
                await Task.yield()
            }
            XCTAssertEqual(current.viewControllers.count, 2, "兜底在当前域执行，无需等待策略原目标域的弹窗")
            XCTAssertEqual(blocked.viewControllers.count, 1)
            XCTAssertEqual(tabs.selectedIndex, 0)
        }

        func testInvalidOriginCannotEnterInterceptorDeferredQueue() async throws {
            let probe = OpenProbe()
            var environment = LYRouteEnvironment()
            environment.provide(OpenProbe.self, probe)
            let host = LYSingleStackHost(root: UIViewController())
            let observer = RecordingObserver()
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([OptionsModule.self]),
                environment: environment,
                interceptors: [LYRouteInterceptor(name: "always.defer") { _ in
                    probe.interceptorCalls += 1
                    return .deferUntilReady
                }],
                observers: [observer],
                allowsUnregistered: true
            )
            defer { router.tearDown() }
            let detachedSource = UIViewController()

            let result = await router.open(.club("one"), source: .push, options: .init(from: detachedSource))
            XCTAssertEqual(result, .failed(.contextChanged))
            XCTAssertNil(router.pending)
            XCTAssertEqual(probe.interceptorCalls, 0)
            XCTAssertEqual(observer.settled.map(\.1), [.failed(.contextChanged)])
        }

        func testDeferredOriginBecomingHiddenIsDroppedWithoutSecondSettlement() async throws {
            let probe = OpenProbe()
            let host = LYSingleStackHost(root: UIViewController())
            host.isReady = false
            let observer = RecordingObserver()
            let router = try makeOptionsRouter(host: host, probe: probe, observers: [observer])
            defer { router.tearDown() }
            let source = try XCTUnwrap(host.navigationController.topViewController)
            let result = await router.open(.club("one"), source: .push, options: .init(from: source))
            XCTAssertEqual(result, .deferred)

            host.navigationController.pushViewController(UIViewController(), animated: false)
            host.isReady = true
            router.navigationDidStabilize()
            for _ in 0 ..< 5 {
                await Task.yield()
            }

            XCTAssertNil(router.pending)
            XCTAssertEqual(probe.handlerCalls, 0)
            XCTAssertEqual(observer.settled.map(\.1), [.deferred])
            XCTAssertEqual(observer.dropped, [.originUnavailable])
        }

        func testDisabledFallbackUsesCurrentPlacementWhenSchedulingPending() throws {
            let host = makeTabHost()
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([DisabledPlacedModule.self]),
                fallback: .placeholder,
                allowsUnregistered: true
            )
            defer { router.tearDown() }

            XCTAssertEqual(router.placement(of: .settings), .current)
        }
    }

    @MainActor
    private final class BlockedNavigationController: UINavigationController {
        var blocker: UIViewController?

        override var presentedViewController: UIViewController? {
            blocker ?? super.presentedViewController
        }
    }

    @MainActor
    private final class AnimationRecordingNavigationController: UINavigationController {
        var lastSetAnimated: Bool?

        override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
            lastSetAnimated = animated
            super.setViewControllers(viewControllers, animated: animated)
        }
    }

    private struct NonanimatedModule: LYRouteModule {
        static let moduleID = "nonanimated"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            builder.page(.club) { route, context in
                guard case let .club(id) = route else { return }
                context.show(identity: PageIdentity.club(id), animated: false) { TestPage(.club(id)) }
            }
        }
    }

    private struct DisabledPlacedModule: LYRouteModule {
        static let moduleID = "disabled.placed"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            builder.page(.settings, policy: .init(status: .disabled, placement: LYRoutePlacement("me"), allowsExternal: true)) { _, _ in
                XCTFail("禁用路由应进入兜底")
            }
        }
    }

    @MainActor
    private final class OpenProbe {
        var options: LYOpenOptions?
        var route: AppRoute?
        var handlerCalls = 0
        var interceptorCalls = 0
    }

    private struct OptionsModule: LYRouteModule {
        static let moduleID = "options"
        let probe: OpenProbe

        init(environment: LYRouteEnvironment) throws {
            probe = try environment.require(OpenProbe.self)
        }

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            let probe = probe
            builder.url("club/<id>", parse: { $0["id"].map(AppRoute.club) }, print: { route in
                if case let .club(id) = route { LYURLValues(path: ["id": id]) } else { nil }
            })
            builder.action(.club, policy: .init(allowsExternal: true, validate: { route in
                if case let .club(id) = route { !id.isEmpty } else { false }
            })) { route, context in
                probe.handlerCalls += 1
                probe.route = route
                probe.options = context.options
                context.markPerformed()
            }
            builder.action(.profile) { route, context in
                probe.handlerCalls += 1
                probe.route = route
                probe.options = context.options
                context.markPerformed()
            }
            builder.page(.settings, policy: .init(status: .disabled)) { _, _ in
                XCTFail("禁用路由应走兜底")
            }
            builder.page(.wallet, policy: .init(status: .placeholder)) { _, _ in
                XCTFail("占位路由应走兜底")
            }
        }
    }

    /// `default` 使用请求动画，`override` 显式传入 `animated: true`。
    private struct ReplaceModule: LYRouteModule {
        static let moduleID = "replace"

        init(environment: LYRouteEnvironment) {}

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            builder.page(.club) { route, context in
                guard case let .club(id) = route else { return }
                if id == "override" {
                    context.replaceStack([UIViewController()], animated: true)
                } else {
                    context.replaceStack([UIViewController()])
                }
            }
        }
    }

    @MainActor
    private func makeOptionsRouter(
        host: LYSingleStackHost,
        probe: OpenProbe,
        observers: [RecordingObserver] = [],
        fallback: LYRouteFallback<AppRoute>? = nil
    ) throws -> LYStackRouter<AppRoute> {
        var environment = LYRouteEnvironment()
        environment.provide(OpenProbe.self, probe)
        return try LYStackRouter<AppRoute>.build(
            host: host,
            modules: .explicit([OptionsModule.self]),
            environment: environment,
            interceptors: [LYRouteInterceptor(name: "probe") { request in
                probe.interceptorCalls += 1
                if request.route == .club("redirect") { return .redirect(.profile("redirected")) }
                return .proceed
            }],
            observers: observers,
            url: LYURLConfiguration(schemes: ["test"]),
            fallback: fallback,
            allowsUnregistered: true
        )
    }

    @MainActor
    private final class ShowProbe {
        let gate = Gate()
        var createdCount = 0
        var preparedOptions: LYOpenOptions?

        func makePage() -> UIViewController {
            createdCount += 1
            return TestPage(nil)
        }
    }

    private struct ShowModule: LYRouteModule {
        static let moduleID = "show.options"
        let probe: ShowProbe

        init(environment: LYRouteEnvironment) throws {
            probe = try environment.require(ShowProbe.self)
        }

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            let probe = probe
            builder.page(.club) { _, context in context.show { probe.makePage() } }
            builder.page(.profile) { _, context in context.show(animated: false) { probe.makePage() } }
            builder.page(.room) { _, context in context.show(animated: true) { probe.makePage() } }
            builder.page(.slowChat) { _, context in
                context.prepare { context in
                    await probe.gate.wait()
                    guard await context.isStillValid() else { return }
                    probe.preparedOptions = context.options
                    context.show { probe.makePage() }
                }
            }
        }
    }

    @MainActor
    private final class OptionsCustomHost: LYRouterHost {
        let activeNavigationController: UINavigationController? = UINavigationController(rootViewController: UIViewController())
        let routerSessionID: String? = nil
        let isRouterReady = true
        var options: LYOpenOptions?
        var displayedPage: UIViewController?

        var routerRootViewController: UIViewController? {
            activeNavigationController
        }

        func customShow(
            _ page: @autoclosure () -> UIViewController,
            identity: AnyHashable?,
            in navigationController: UINavigationController,
            options: LYOpenOptions
        ) -> LYOpenResult? {
            self.options = options
            let made = page()
            XCTAssertTrue(made === page(), "宿主多次读取页面时构造闭包只执行一次")
            displayedPage = made
            return .created
        }
    }

    @MainActor
    private final class LegacyCustomHost: LYRouterHost {
        let activeNavigationController: UINavigationController? = UINavigationController(rootViewController: UIViewController())
        let routerSessionID: String? = nil
        let isRouterReady = true
        var calls = 0
        var displayedPage: UIViewController?

        var routerRootViewController: UIViewController? {
            activeNavigationController
        }

        func customShow(
            _ page: @autoclosure () -> UIViewController,
            identity: AnyHashable?,
            in navigationController: UINavigationController
        ) -> LYOpenResult? {
            calls += 1
            displayedPage = page()
            return .created
        }
    }

    @MainActor
    private func makeShowRouter(host: any LYRouterHost, probe: ShowProbe) throws -> LYStackRouter<AppRoute> {
        var environment = LYRouteEnvironment()
        environment.provide(ShowProbe.self, probe)
        return try LYStackRouter<AppRoute>.build(
            host: host,
            modules: .explicit([ShowModule.self]),
            environment: environment,
            allowsUnregistered: true
        )
    }
#endif
