#if canImport(UIKit)
    import DemoRouteContract
    import DemoUIKit
    import LYStackRouter
    import UIKit
    import XCTest
    import DemoMessagingFeature

    @MainActor
    final class ModuleRegistrationTests: XCTestCase {
        func testIndependentAssemblyRegistersItsURLsAndExternalPolicy() throws {
            var environment = LYRouteEnvironment()
            environment.provide(DemoMetrics.self, DemoMetrics())
            let router = try LYStackRouter<DemoRoute>.build(
                modules: .explicit([MessagesRouteModule.self]),
                environment: environment,
                url: LYURLConfiguration(schemes: ["lydemo"]),
                fallback: .placeholder,
                allowsUnregistered: true
            )
            XCTAssertEqual(router.moduleIDs, ["messages"])
            XCTAssertTrue(router.canOpen(.chat("c1"), source: .push))
            XCTAssertEqual(try router.route(for: XCTUnwrap(URL(string: "lydemo://chat/c1"))), .chat("c1"))
            XCTAssertFalse(router.canOpen(.wallet, source: .push))
            XCTAssertTrue(router.canOpen(.wallet), "独立 Demo 用兜底处理未组装的模块")
            router.tearDown()
        }
    }
#endif
