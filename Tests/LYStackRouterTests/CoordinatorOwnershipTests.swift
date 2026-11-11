#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 文档推荐的持有方式：协调器同时持有宿主与路由器；路由器只弱引用宿主。
    @MainActor
    final class CoordinatorOwnershipTests: XCTestCase {
        func testInlineHostIsReleasedAndRouterStopsNavigating() throws {
            let router = try LYStackRouter<AppRoute>.build(
                host: LYSingleStackHost(root: UIViewController()),
                modules: .explicit([CommunityModule.self]),
                environment: makeEnvironment(),
                allowsUnregistered: true
            )
            XCTAssertEqual(router.request(.club("x")), .ignored, "没人持有的宿主随即释放，路由器无法导航")
        }

        func testCoordinatorKeepsNavigatingAfterAssemblyReturns() throws {
            let coordinator = try DemoCoordinator()
            XCTAssertEqual(coordinator.router.request(.club("x")), .created)
            coordinator.tearDown()
            XCTAssertEqual(coordinator.router.request(.club("y")), .failed(.stopped))
        }

        func testReleasingCoordinatorReleasesHostAndRouter() throws {
            weak var weakRouter: LYStackRouter<AppRoute>?
            weak var weakHost: LYSingleStackHost?
            do {
                let coordinator = try DemoCoordinator()
                weakRouter = coordinator.router
                weakHost = coordinator.host
                XCTAssertEqual(coordinator.router.request(.club("x")), .created)
            }
            XCTAssertNil(weakRouter, "宿主与路由器之间不能形成循环持有")
            XCTAssertNil(weakHost)
        }
    }

    /// 与 README、接入指南一致的协调器写法。
    @MainActor
    private final class DemoCoordinator {
        let host: LYSingleStackHost
        let router: LYStackRouter<AppRoute>

        init() throws {
            let host = LYSingleStackHost(root: UIViewController())
            self.host = host
            router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CommunityModule.self]),
                environment: makeEnvironment(),
                allowsUnregistered: true
            )
        }

        func tearDown() {
            router.tearDown()
        }
    }
#endif
