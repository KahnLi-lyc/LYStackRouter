#if canImport(UIKit)
    import DemoRouteContract
    import DemoUIKit
    import LYStackRouter
    import UIKit
    import XCTest
    import DemoCommunityFeature

    @MainActor
    final class ModuleRegistrationTests: XCTestCase {
        func testIndependentAssemblyRegistersItsURLsAndExternalPolicy() throws {
            var environment = LYRouteEnvironment()
            environment.provide(DemoMetrics.self, DemoMetrics())
            let router = try LYStackRouter<DemoRoute>.build(
                modules: .explicit([CommunityRouteModule.self]),
                environment: environment,
                url: LYURLConfiguration(schemes: ["lydemo"]),
                fallback: .placeholder,
                allowsUnregistered: true
            )
            XCTAssertEqual(router.moduleIDs, ["community"])
            XCTAssertTrue(router.canOpen(.club("A"), source: .push))
            XCTAssertEqual(try router.route(for: XCTUnwrap(URL(string: "lydemo://club/A"))), .club("A"))
            XCTAssertFalse(router.canOpen(.wallet, source: .push))
            XCTAssertTrue(router.canOpen(.wallet), "独立 Demo 用兜底处理未组装的模块")
            router.tearDown()
        }
    }
#endif
