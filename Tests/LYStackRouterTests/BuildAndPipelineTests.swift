#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    @MainActor
    final class BuildAndPipelineTests: XCTestCase {
        // MARK: - Build

        func testMissingDependencyNamesModuleAndType() {
            XCTAssertThrowsError(try LYStackRouter<AppRoute>.build(modules: .explicit([CommunityModule.self]))) { error in
                XCTAssertEqual(error as? LYRouteBuildError, .missingDependency(module: "community", type: "Dependencies"))
            }
        }

        func testDuplicateModuleIsRejected() {
            XCTAssertThrowsError(
                try LYStackRouter<AppRoute>.build(
                    modules: .explicit([CommunityModule.self, CommunityModule.self]),
                    environment: makeEnvironment()
                )
            ) { error in
                XCTAssertEqual(error as? LYRouteBuildError, .duplicateModule(["community"]))
            }
        }

        func testExhaustiveBuildRequiresEveryKindWithoutFallback() {
            XCTAssertThrowsError(
                try LYStackRouter<AppRoute>.build(modules: .explicit([CommunityModule.self]), environment: makeEnvironment())
            ) { error in
                XCTAssertEqual(
                    error as? LYRouteBuildError,
                    .missingRegistration(["chat", "room", "slowChat"])
                )
            }
        }

        // MARK: - Fallback and Rewrite

        func testFallbackShowsPlaceholderForUnregisteredKind() throws {
            let host = LYSingleStackHost(root: UIViewController())
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self]),
                environment: makeEnvironment(),
                fallback: .placeholder,
                allowsUnregistered: true
            )
            XCTAssertEqual(router.request(.chat("s1")), .created)
            XCTAssertTrue(host.navigationController.topViewController is LYRoutePlaceholderViewController)
        }

        func testFallbackAloneDoesNotDisableExhaustiveCheck() {
            XCTAssertThrowsError(
                try LYStackRouter<AppRoute>.build(
                    modules: .explicit([CommunityModule.self]),
                    environment: makeEnvironment(),
                    fallback: .placeholder
                )
            ) { error in
                XCTAssertEqual(error as? LYRouteBuildError, .missingRegistration(["chat", "room", "slowChat"]))
            }
        }

        func testRewriteDisablesKindWithoutFallback() throws {
            let host = makeTabHost()
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self, ChatModule.self]),
                environment: makeEnvironment()
            )
            router.rewrite = LYRouteRewrite(disabledKinds: ["club"])
            XCTAssertEqual(router.request(.club("x")), .failed(.unavailable))
            router.rewrite = .none
            XCTAssertEqual(router.request(.club("x")), .created)
        }

        func testFallbackHandlesPlaceholderAndDisabledKinds() throws {
            struct PartialModule: LYRouteModule {
                static let moduleID = "partial"
                init(environment: LYRouteEnvironment) {}
                func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
                    builder.page(.club, policy: .init(status: .placeholder)) { _, _ in XCTFail("占位路由不应调用处理器") }
                    builder.page(.profile, policy: .init(status: .disabled)) { _, _ in XCTFail("禁用路由不应调用处理器") }
                }
            }
            let host = LYSingleStackHost(root: UIViewController())
            var reasons: [LYRouteFallbackReason] = []
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([PartialModule.self]),
                fallback: LYRouteFallback { _, reason, context in
                    reasons.append(reason)
                    context.show { UIViewController() }
                },
                allowsUnregistered: true
            )
            XCTAssertEqual(router.request(.club("x")), .created)
            XCTAssertEqual(router.request(.profile("a")), .created)
            XCTAssertEqual(router.request(.wallet), .created)
            XCTAssertEqual(reasons, [.placeholder, .unavailable, .unregistered])
        }

        func testDisabledKindWithoutFallbackFailsAndPlaceholderRunsHandler() throws {
            struct PartialModule: LYRouteModule {
                static let moduleID = "partial"
                init(environment: LYRouteEnvironment) {}
                func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
                    builder.page(.club, policy: .init(status: .placeholder)) { _, context in context.show { UIViewController() } }
                    builder.page(.profile, policy: .init(status: .disabled)) { _, _ in }
                }
            }
            let host = LYSingleStackHost(root: UIViewController())
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([PartialModule.self]),
                allowsUnregistered: true
            )
            XCTAssertEqual(router.request(.club("x")), .created, "没有兜底时占位路由仍由自己的处理器展示")
            XCTAssertEqual(router.request(.profile("a")), .failed(.unavailable))
            XCTAssertEqual(router.request(.wallet), .failed(.unregistered))
        }

        // MARK: - Interceptors and Observers

        func testRedirectRunsFullAdmissionAndLoopIsStopped() throws {
            let host = makeTabHost()
            let toProfile = LYRouteInterceptor<AppRoute>(name: "redirect", kinds: [.club]) { _ in .redirect(.profile("login")) }
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self, ChatModule.self]),
                environment: makeEnvironment(),
                interceptors: [toProfile]
            )
            XCTAssertEqual(router.request(.club("x")), .created)
            let top = host.allNavigationControllers[0].topViewController as? TestPage
            XCTAssertEqual(top?.identity, .profile("login"))

            let loop = LYRouteInterceptor<AppRoute>(name: "loop", kinds: [.club]) { _ in .redirect(.club("again")) }
            let loopingHost = makeTabHost()
            let looping = try LYStackRouter<AppRoute>.build(
                host: loopingHost,
                modules: .explicit([CommunityModule.self, ChatModule.self]),
                environment: makeEnvironment(),
                interceptors: [loop]
            )
            XCTAssertEqual(looping.request(.club("x")), .failed(.rejected("redirectLoop")))
            withExtendedLifetime(loopingHost) {}
        }

        func testObserverSeesWillOpenAndSettlements() throws {
            let observer = RecordingObserver()
            // 路由器弱引用宿主，宿主由调用方持有。
            let host = makeTabHost()
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self, ChatModule.self]),
                environment: makeEnvironment(),
                observers: [observer]
            )
            router.request(.club("x"))
            router.request(.club(""))
            XCTAssertEqual(observer.willOpen, [.club])
            XCTAssertEqual(observer.settled.map(\.1), [.created, .failed(.invalidParameter)])
            withExtendedLifetime(host) {}
        }
    }
#endif
