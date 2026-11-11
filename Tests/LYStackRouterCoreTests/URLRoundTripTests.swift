import XCTest
@testable import LYStackRouterCore

/// 生成的 URL 必须能被整张路由表解析回同一路由；被更具体的模板截获时换用别名模板，都不行时返回 nil。
@MainActor
final class URLRoundTripTests: XCTestCase {
    // MARK: - Shadowing

    func testShadowedIDIsNotGenerated() throws {
        let registry = try makeRegistry(withAlias: false)
        XCTAssertEqual(registry.url(for: .club("9"), configuration: testConfiguration)?.absoluteString, "myapp://club/9")
        XCTAssertNil(
            registry.url(for: .club("new"), configuration: testConfiguration),
            "club/new 会被字面模板解析成另一个路由，不能返回"
        )
        XCTAssertNil(registry.url(for: .club("new"), configuration: testConfiguration, universalLinkHost: "app.example.com"))
    }

    func testShadowedIDFallsBackToAliasTemplate() throws {
        let registry = try makeRegistry(withAlias: true)
        let custom = try XCTUnwrap(registry.url(for: .club("new"), configuration: testConfiguration))
        XCTAssertEqual(custom.absoluteString, "myapp://c/new")
        XCTAssertEqual(registry.route(for: custom, configuration: testConfiguration), .club("new"))
        let link = try XCTUnwrap(
            registry.url(for: .club("new"), configuration: testConfiguration, universalLinkHost: "app.example.com")
        )
        XCTAssertEqual(link.absoluteString, "https://app.example.com/c/new")
        XCTAssertEqual(
            registry.url(for: .club("9"), configuration: testConfiguration)?.absoluteString,
            "myapp://club/9",
            "未被遮蔽时仍使用排序靠前的模板"
        )
    }

    // MARK: - Normalizing Parse

    func testRouteThatParseNormalizesIsNotGenerated() throws {
        let registry = try makeReferenceRegistry()
        XCTAssertNil(
            registry.url(for: .room("7", entry: "unknown"), configuration: testConfiguration),
            "parse 会把未知 entry 规范为 notification，生成的 URL 打开后不是原路由"
        )
        XCTAssertNotNil(registry.url(for: .room("7", entry: "circle"), configuration: testConfiguration))
    }

    // MARK: - Encoding

    func testSpecialCharactersRoundTrip() throws {
        let registry = try makeReferenceRegistry()
        for original: TestRoute in [.club("中文"), .club("a b"), .club("100%"), .web("中文/a b/100%")] {
            for host in [nil, "app.example.com"] {
                let generated = try XCTUnwrap(
                    registry.url(for: original, configuration: testConfiguration, universalLinkHost: host),
                    "\(original)"
                )
                XCTAssertEqual(
                    registry.route(for: generated, configuration: testConfiguration),
                    original,
                    generated.absoluteString
                )
            }
        }
    }

    func testQuerySpecialCharactersRoundTrip() throws {
        var builder = TestRegistry.Builder()
        builder.url("q/<id>", parse: { values in
            guard let id = values["id"], let type = values.query["type"] else { return nil }
            return .chat(id, type: type)
        }, print: {
            if case let .chat(id, type) = $0 { LYURLValues(path: ["id": id], query: ["type": type]) } else { nil }
        })
        let registry = try builder.build(requireExhaustive: false)
        let original = TestRoute.chat("s 1", type: "a&b=c 中文%")
        let generated = try XCTUnwrap(registry.url(for: original, configuration: testConfiguration))
        XCTAssertEqual(registry.route(for: generated, configuration: testConfiguration), original, generated.absoluteString)
    }

    // MARK: - Helpers

    /// `club/<id>` 与字面模板 `club/new` 合法共存；可选的别名模板 `c/<id>` 能表达任意俱乐部。
    private func makeRegistry(withAlias: Bool) throws -> TestRegistry {
        var builder = TestRegistry.Builder()
        builder.url("club/<id>", parse: { $0["id"].map(TestRoute.club) }, print: {
            if case let .club(id) = $0 { LYURLValues(path: ["id": id]) } else { nil }
        })
        builder.url("club/new", parse: { _ in .home }, print: { $0 == .home ? LYURLValues() : nil })
        if withAlias {
            builder.url("c/<id>", parse: { $0["id"].map(TestRoute.club) }, print: {
                if case let .club(id) = $0 { LYURLValues(path: ["id": id]) } else { nil }
            })
        }
        return try builder.build(requireExhaustive: false)
    }
}
