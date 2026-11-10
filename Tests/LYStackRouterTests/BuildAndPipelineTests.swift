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
                fallback: .placeholder
            )
            XCTAssertEqual(router.request(.chat("s1")), .created)
            XCTAssertTrue(host.navigationController.topViewController is LYRoutePlaceholderViewController)
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
