import XCTest
@testable import LYStackRouterCore

@MainActor
final class RegistryTests: XCTestCase {
    func testExhaustiveBuildReportsEveryMissingKind() {
        var builder = TestRegistry.Builder()
        builder.page(.home) { _, _ in }
        XCTAssertThrowsError(try builder.build(requireExhaustive: true)) { error in
            guard case let LYRouteBuildError.missingRegistration(kinds) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(kinds, ["chat", "club", "friends", "profile", "room", "wallet", "web"])
        }
    }

    func testNonExhaustiveBuildAllowsMissingKinds() throws {
        var builder = TestRegistry.Builder()
        builder.page(.home) { _, _ in }
        let registry = try builder.build(requireExhaustive: false)
        XCTAssertEqual(registry.registeredKinds, [.home])
        XCTAssertNil(registry.policy(for: .club))
    }

    func testDuplicateRegistrationNamesBothModules() {
        var builder = TestRegistry.Builder()
        builder.moduleID = "first"
        builder.page(.home) { _, _ in }
        builder.moduleID = "second"
        builder.action(.home) { _, _ in }
        XCTAssertThrowsError(try builder.build(requireExhaustive: false)) { error in
            guard case let LYRouteBuildError.duplicateRegistration(items) = error else { return XCTFail("\(error)") }
            XCTAssertEqual(items.count, 1)
            XCTAssertTrue(items[0].contains("first") && items[0].contains("second"))
        }
    }

    func testPolicyAndHandlerKindAreKept() throws {
        var builder = TestRegistry.Builder()
        builder.action(.wallet, policy: .init(status: .disabled, placement: LYRoutePlacement("me"), allowsExternal: true)) { _, _ in }
        let registry = try builder.build(requireExhaustive: false)
        let policy = try XCTUnwrap(registry.policy(for: .wallet))
        XCTAssertEqual(policy.status, .disabled)
        XCTAssertEqual(policy.placement, LYRoutePlacement("me"))
        XCTAssertTrue(policy.allowsExternal)
        XCTAssertEqual(registry.entries[.wallet]?.handlerKind, .action)
    }

    func testInvalidTemplateFailsBuild() {
        var builder = TestRegistry.Builder()
        builder.url("web/<path:rest>/tail", parse: { _ in nil }, print: { _ in nil })
        XCTAssertThrowsError(try builder.build(requireExhaustive: false)) { error in
            guard case LYRouteBuildError.invalidURLPattern = error else { return XCTFail("\(error)") }
        }
    }

    func testSameShapeTemplatesConflictAcrossModules() {
        var builder = TestRegistry.Builder()
        builder.moduleID = "club"
        builder.url("club/<id>", parse: { $0["id"].map(TestRoute.club) }, print: { _ in nil })
        builder.moduleID = "other"
        builder.url("club/<clubID>", parse: { _ in nil }, print: { _ in nil })
        XCTAssertThrowsError(try builder.build(requireExhaustive: false)) { error in
            guard case let LYRouteBuildError.urlConflict(items) = error else { return XCTFail("\(error)") }
            XCTAssertTrue(items[0].contains("club") && items[0].contains("other"))
        }
    }

    func testEnvironmentRequireReportsMissingType() throws {
        var environment = LYRouteEnvironment()
        environment.provide(Int.self, 42)
        XCTAssertEqual(try environment.require(Int.self), 42)
        XCTAssertThrowsError(try environment.require(String.self)) { error in
            XCTAssertEqual((error as? LYRouteEnvironment.MissingDependency)?.type, "String")
        }
    }
}
