#if canImport(UIKit)
    @testable import LYStackRouterDiscovery
    import UIKit
    import XCTest

    @MainActor
    final class DiscoveryTests: XCTestCase {
        // MARK: - Discovery

        func testSectionRecordsListAnnotatedModulesOnly() {
            let found = Set(LYRouteDiscovery.moduleTypes().map(ObjectIdentifier.init))
            XCTAssertTrue(found.contains(ObjectIdentifier(AlphaModule.self)))
            XCTAssertTrue(found.contains(ObjectIdentifier(BetaModule.self)))
            XCTAssertTrue(found.contains(ObjectIdentifier(OtherRouteModule.self)))
            XCTAssertFalse(found.contains(ObjectIdentifier(FakeAlphaModule.self)), "未标注的类型不会被发现")
        }

        func testDiscoveredIsFilteredByRouteAndSortedByModuleID() {
            XCTAssertEqual(moduleIDs(LYRouteModuleSet<DiscoveryRoute>.discovered.resolve()), ["alpha", "beta"])
            XCTAssertEqual(moduleIDs(LYRouteModuleSet<OtherRoute>.discovered.resolve()), ["other"])
        }

        func testDiscoveredBuildBehavesLikeExplicit() throws {
            for modules in [
                LYRouteModuleSet<DiscoveryRoute>.discovered,
                .explicit([AlphaModule.self, BetaModule.self])
            ] {
                let host = LYSingleStackHost(root: UIViewController())
                let router = try LYStackRouter<DiscoveryRoute>.build(
                    host: host,
                    modules: modules,
                    url: LYURLConfiguration(schemes: ["demo"])
                )
                XCTAssertEqual(router.request(.alpha), .created)
                let url = try XCTUnwrap(URL(string: "demo://beta/7"))
                XCTAssertEqual(router.route(for: url), .beta("7"))
                XCTAssertEqual(router.request(.beta("7")), .created)
                XCTAssertEqual(router.request(.alpha), .created, "没有身份的页面每次新建")
                XCTAssertEqual(host.navigationController.viewControllers.count, 4)
            }
        }

        // MARK: - Mixing

        func testExcludingDiscoveredModuleIsCaughtByExhaustiveCheck() {
            XCTAssertThrowsError(
                try LYStackRouter<DiscoveryRoute>.build(modules: .discovered(excluding: ["beta"]))
            ) { error in
                XCTAssertEqual(error as? LYRouteBuildError, .missingRegistration(["beta"]))
            }
        }

        func testDoubleReplacesExcludedModuleWithSameID() throws {
            let host = LYSingleStackHost(root: UIViewController())
            let router = try LYStackRouter<DiscoveryRoute>.build(
                host: host,
                modules: .discovered(plus: [FakeAlphaModule.self], excluding: ["alpha"])
            )
            XCTAssertEqual(router.request(.alpha), .created)
            XCTAssertEqual((host.navigationController.topViewController as? MarkedPage)?.mark, "fake alpha")
        }

        func testAdditionalDiscoveredTypeIsRegisteredOnce() {
            let modules = LYRouteModuleSet<DiscoveryRoute>.discovered(plus: [AlphaModule.self]).resolve()
            XCTAssertEqual(moduleIDs(modules), ["alpha", "beta"])
        }

        func testDoubleWithoutExcludingIsDuplicateModule() {
            XCTAssertThrowsError(
                try LYStackRouter<DiscoveryRoute>.build(modules: .discovered(plus: [FakeAlphaModule.self]))
            ) { error in
                XCTAssertEqual(error as? LYRouteBuildError, .duplicateModule(["alpha"]))
            }
        }

        // MARK: - Helpers

        /// 不写 `map(\.moduleID)`：Swift 6.4.2 对存在类型元类型的 key path 会在 SILGen 阶段崩溃。
        private func moduleIDs<Route>(_ modules: [any LYRouteModule<Route>.Type]) -> [String] {
            // swiftformat:disable:next preferKeyPath
            modules.map { $0.moduleID }
        }
    }
#endif
