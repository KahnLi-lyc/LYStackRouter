import Foundation
import LYStackRouter
import UIKit

/// 将真实导航和清理结果写入沙盒，模拟器与真机使用同一套断言。
@MainActor
final class CompatibilityProbe {
    private let router: LYStackRouter<CompatibilityRoute>
    private let host: LYSingleStackHost
    private let root: CompatibilityPage
    private let gate: CompatibilityGate
    private var checks: [String] = []
    private var preparationResult: LYOpenResult?
    private var started = false

    init(router: LYStackRouter<CompatibilityRoute>, host: LYSingleStackHost, root: CompatibilityPage, gate: CompatibilityGate) {
        self.router = router
        self.host = host
        self.root = root
        self.gate = gate
    }

    func run() async {
        guard !started else { return }
        started = true
        var passed = false
        defer {
            gate.release()
            router.tearDown()
            root.showReport(passed: passed, count: checks.count)
            Self.writeReport(passed: passed, checks: checks)
        }
        do {
            try await waitUntil { self.root.appeared && self.root.viewIfLoaded?.window?.isKeyWindow == true && UIApplication.shared.applicationState == .active }
            host.isReady = true
            router.navigationDidStabilize()
            try expect(router.moduleIDs == ["compatibility"], "module registered after linking")
            let oldClient = router.makeClient(from: root)
            let created = await oldClient.open(.detail(1), options: .init(animated: false))
            try expect(created == .created && host.navigationController.viewControllers.count == 2, "typed client creates page")
            _ = await router.open(.detail(2), options: .init(animated: false))
            let removed = host.navigationController.topViewController as? CompatibilityPage
            let reused = await router.open(.detail(1), options: .init(animated: false))
            try expect(reused == .reused && host.navigationController.viewControllers.count == 2 && removed?.removedCount == 1, "identity reuse cleans removed page once")
            router.invalidateContext()
            let invalid = await oldClient.open(.detail(3), options: .init(animated: false))
            try expect(invalid == .failed(.contextChanged) && host.navigationController.viewControllers.count == 2, "old client loses capability")
            let fresh = router.makeClient()
            let freshResult = await fresh.open(.detail(3), options: .init(animated: false))
            try expect(freshResult == .created, "fresh client remains usable")

            let caller = Task { @MainActor in
                self.preparationResult = await self.router.open(.preparation, options: .init(animated: false))
            }
            defer { caller.cancel() }
            try await waitUntil { self.gate.waiting }
            caller.cancel()
            try await waitUntil { self.preparationResult != nil }
            try expect(preparationResult == .failed(.contextChanged) && !router.isNavigating, "caller cancellation releases uncooperative preparation")
            gate.release()
            let action = await router.open(.action)
            try expect(action == .performed, "action reports performed")

            let presented = await router.open(.modal, options: .init(animated: false))
            let modal = host.navigationController.presentedViewController as? UINavigationController
            try expect(presented == .created && modal != nil, "modal creates navigation flow")
            let modalRoot = modal?.topViewController as? CompatibilityPage
            let dismissed = await router.makeClient(from: modalRoot).dismiss(animated: false)
            try expect(dismissed == .performed && host.navigationController.presentedViewController == nil && modalRoot?.removedCount == 1, "modal dismissal cleans flow once")
            while host.navigationController.viewControllers.count > 1 {
                let back = await router.makeClient().dismiss(animated: false)
                try expect(back == .reused, "client dismiss returns within source stack")
            }
            passed = true
        } catch {
            checks.append("FAIL: \(error)")
        }
    }

    func stop() {
        gate.release()
        router.tearDown()
    }

    static func writeReport(passed: Bool, checks: [String]) {
        #if ROUTER_DISCOVERY
            let product = "LYStackRouterDiscovery"
        #else
            let product = "LYStackRouter"
        #endif
        do {
            let directory = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            let report: [String: Any] = ["passed": passed, "checks": checks, "product": product, "systemVersion": UIDevice.current.systemVersion]
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: directory.appendingPathComponent("compatibility-report.json"), options: .atomic)
            print("LYRouterCompatibility \(passed ? "PASS" : "FAIL") \(product) \(checks.count)")
        } catch {
            print("LYRouterCompatibility REPORT ERROR: \(error)")
        }
    }

    private func expect(_ condition: Bool, _ name: String) throws {
        guard condition else { throw ProbeFailure(message: name) }
        checks.append(name)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { throw ProbeFailure(message: "condition timed out after \(checks.count) checks") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private struct ProbeFailure: Error, CustomStringConvertible {
    let message: String
    var description: String {
        message
    }
}
