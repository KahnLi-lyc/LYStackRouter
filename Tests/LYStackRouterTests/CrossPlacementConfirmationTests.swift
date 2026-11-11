#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 确认门在目标域展示后，应从目标页面重新取得执行权。
    @MainActor
    final class CrossPlacementConfirmationTests: XCTestCase {
        func testConfirmationRebindsTargetOriginAndPreservesExtrasAndAnimation() async throws {
            let probe = CrossPlacementProbe()
            let host = makeTabHost()
            var environment = LYRouteEnvironment()
            environment.provide(CrossPlacementProbe.self, probe)
            let router = try LYStackRouter<AppRoute>.build(
                host: host,
                modules: .explicit([CrossPlacementModule.self]),
                environment: environment,
                allowsUnregistered: true
            )
            defer { router.tearDown() }
            let initialNavigation = host.allNavigationControllers[0]
            let targetNavigation = host.allNavigationControllers[2]
            let initialOrigin = try XCTUnwrap(initialNavigation.topViewController)
            let targetOrigin = try XCTUnwrap(targetNavigation.topViewController)
            var presented: (@MainActor () -> Void)?
            var confirm: (@MainActor () -> Void)?
            router.confirmationPresenter = { _, navigation, action, onPresented in
                XCTAssertTrue(navigation === targetNavigation)
                confirm = action
                presented = onPresented
                return true
            }

            let result = router.request(.settings, options: .init(animated: false, from: initialOrigin, extras: ["entry": "toolbar"]))
            XCTAssertEqual(result, .awaitingConfirmation)
            XCTAssertTrue(host.activeNavigationController === targetNavigation)
            XCTAssertTrue(probe.initialOptions?.from === initialOrigin)
            let onPresented = try XCTUnwrap(presented)
            let onConfirm = try XCTUnwrap(confirm)
            onPresented()
            onConfirm()
            onConfirm()
            let deadline = Date().addingTimeInterval(2)
            while probe.confirmed == 0, Date() < deadline {
                try? await Task.sleep(nanoseconds: 5_000_000)
            }

            XCTAssertEqual(probe.confirmed, 1)
            XCTAssertEqual(probe.continuationOptions?.animated, false)
            XCTAssertEqual(probe.continuationOptions?.extras["entry"] as? String, "toolbar")
            XCTAssertTrue(probe.continuationOptions?.from === targetOrigin)
            XCTAssertTrue(probe.continuationNavigation === targetNavigation)
            XCTAssertEqual(initialNavigation.viewControllers.count, 1)
            XCTAssertEqual(targetNavigation.viewControllers.count, 2)
            XCTAssertEqual((targetNavigation.topViewController as? TestPage)?.identity, .profile("confirmed"))
        }
    }

    @MainActor
    private final class CrossPlacementProbe {
        var initialOptions: LYOpenOptions?
        var continuationOptions: LYOpenOptions?
        weak var continuationNavigation: UINavigationController?
        var confirmed = 0
    }

    private struct CrossPlacementModule: LYRouteModule {
        static let moduleID = "confirmation.crossPlacement"
        private let probe: CrossPlacementProbe

        init(environment: LYRouteEnvironment) throws {
            probe = try environment.require(CrossPlacementProbe.self)
        }

        func register(into builder: inout LYStackRouteRegistry<AppRoute>.Builder) {
            let probe = probe
            builder.page(.settings, policy: .init(placement: LYRoutePlacement("me"))) { _, context in
                probe.initialOptions = context.options
                context.confirm(title: "确认", message: nil, confirmTitle: "继续", cancelTitle: "取消") { context in
                    probe.confirmed += 1
                    probe.continuationOptions = context.options
                    probe.continuationNavigation = context.navigationController
                    context.show { TestPage(.profile("confirmed")) }
                }
            }
        }
    }
#endif
