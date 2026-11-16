import XCTest
@testable import LYStackRouterCore

@MainActor
final class InterceptorTests: XCTestCase {
    private func request(_ route: TestRoute) -> LYInterceptRequest<TestRoute> {
        LYInterceptRequest(route: route, source: .user)
    }

    func testHigherPriorityRunsFirstAndStableForTies() {
        var calls: [String] = []
        func recording(_ name: String, priority: Int) -> LYRouteInterceptor<TestRoute> {
            .init(name: name, priority: priority) { _ in
                calls.append(name)
                return .proceed
            }
        }
        let interceptors = [recording("low", priority: 0), recording("high", priority: 10), recording("low2", priority: 0)]
        XCTAssertEqual(LYRouteInterceptor.evaluate(interceptors, request: request(.home)), .proceed)
        XCTAssertEqual(calls, ["high", "low", "low2"])
    }

    func testFirstNonProceedDecisionStopsTheChain() {
        var reachedLast = false
        let interceptors: [LYRouteInterceptor<TestRoute>] = [
            .init(name: "redirect", priority: 5) { _ in .redirect(.home) },
            .init(name: "last") { _ in
                reachedLast = true
                return .proceed
            }
        ]
        XCTAssertEqual(LYRouteInterceptor.evaluate(interceptors, request: request(.wallet)), .redirect(.home))
        XCTAssertFalse(reachedLast)
    }

    func testKindsLimitTheScope() {
        let interceptors: [LYRouteInterceptor<TestRoute>] = [
            .init(name: "clubOnly", kinds: [.club]) { _ in .reject(.permissionDenied) }
        ]
        XCTAssertEqual(LYRouteInterceptor.evaluate(interceptors, request: request(.home)), .proceed)
        XCTAssertEqual(LYRouteInterceptor.evaluate(interceptors, request: request(.club("1"))), .reject(.permissionDenied))
    }

    func testBusinessGateOnlyAffectsConfiguredKinds() {
        let gate = BusinessGate()
        let interceptors: [LYRouteInterceptor<TestRoute>] = [.init(name: "businessGate", kinds: [.wallet]) { _ in gate.ready ? .proceed : .deferUntilReady }]
        XCTAssertEqual(LYRouteInterceptor.evaluate(interceptors, request: request(.home)), .proceed)
        XCTAssertEqual(
            LYRouteInterceptor.evaluate(interceptors, request: request(.wallet)),
            .deferUntilReady
        )
        gate.ready = true
        XCTAssertEqual(
            LYRouteInterceptor.evaluate(interceptors, request: request(.wallet)),
            .proceed
        )
    }
}

@MainActor
private final class BusinessGate {
    var ready = false
}
