import XCTest
@testable import LYStackRouterCore

@MainActor
final class URLRoutingTests: XCTestCase {
    private var registry: TestRegistry!

    override func setUp() async throws {
        registry = try makeReferenceRegistry()
    }

    private func route(_ string: String, rewrite: LYRouteRewrite = .none) -> TestRoute? {
        registry.route(for: url(string), configuration: testConfiguration, rewrite: rewrite)
    }

    // MARK: - Scheme and host

    func testCustomSchemeTreatsHostAsFirstSegment() {
        XCTAssertEqual(route("myapp://club/42"), .club("42"))
        XCTAssertEqual(route("MYAPP://home"), .home)
    }

    func testUniversalLinkRequiresWhitelistedHostAndDropsIt() {
        XCTAssertEqual(route("https://app.example.com/club/42"), .club("42"))
        XCTAssertEqual(route("https://APP.example.com/club/42"), .club("42"))
        XCTAssertNil(route("https://evil.example.com/club/42"))
        XCTAssertNil(route("http://app.example.com/club/42"))
    }

    /// 末尾斜杠与重复斜杠被忽略，不影响段数匹配。
    func testTrailingSlashIsIgnored() {
        XCTAssertEqual(route("myapp://club/42/"), .club("42"))
        XCTAssertEqual(route("https://app.example.com/club/42/"), .club("42"))
    }

    func testSchemeMutationKeepsCaseInsensitiveMatching() {
        var configuration = LYURLConfiguration(schemes: ["initial"])
        configuration.schemes = ["MYAPP"]
        XCTAssertEqual(registry.route(for: url("myapp://club/42"), configuration: configuration), .club("42"))
        configuration.schemes.insert("SECOND")
        XCTAssertEqual(registry.route(for: url("second://club/42"), configuration: configuration), .club("42"))
        XCTAssertEqual(configuration.schemes, ["myapp", "second"])
    }

    func testUniversalLinkHostMutationKeepsCaseInsensitiveMatchingAndGeneration() throws {
        var configuration = LYURLConfiguration(schemes: ["myapp"])
        configuration.universalLinkHosts = ["APP.EXAMPLE.COM"]
        XCTAssertEqual(registry.route(for: url("https://app.example.com/club/42"), configuration: configuration), .club("42"))
        configuration.universalLinkHosts.insert("OTHER.EXAMPLE.COM")
        let generated = try XCTUnwrap(registry.url(for: .club("42"), configuration: configuration, universalLinkHost: "OTHER.EXAMPLE.COM"))
        XCTAssertEqual(generated.absoluteString, "https://other.example.com/club/42")
        XCTAssertEqual(registry.route(for: generated, configuration: configuration), .club("42"))
        XCTAssertEqual(configuration.universalLinkHosts, ["app.example.com", "other.example.com"])
    }

    func testPreferredSchemeMutationUsesNormalizedAllowedScheme() throws {
        var configuration = LYURLConfiguration(schemes: ["myapp", "second"])
        configuration.preferredScheme = "SECOND"
        let generated = try XCTUnwrap(registry.url(for: .club("42"), configuration: configuration))
        XCTAssertEqual(configuration.preferredScheme, "second")
        XCTAssertEqual(generated.absoluteString, "second://club/42")
        XCTAssertEqual(registry.route(for: generated, configuration: configuration), .club("42"))

        configuration.preferredScheme = "UNREGISTERED"
        XCTAssertNil(registry.url(for: .club("42"), configuration: configuration))
    }

    func testEncodedPathSegmentsDecodeOnceAndKeepValueCase() {
        XCTAssertEqual(route("myapp://club/100%25"), .club("100%"))
        XCTAssertEqual(route("myapp://club/a%252Fb"), .club("a%2Fb"))
        XCTAssertEqual(route("myapp://club/MiXeD/"), .club("MiXeD"))
    }

    func testOtherSchemesAndEmptyPathsAreRejected() {
        XCTAssertNil(route("other://club/42"))
        XCTAssertNil(route("https://app.example.com/"))
        XCTAssertNil(route("myapp://"))
    }

    // MARK: - Segments and query

    func testSegmentCountIsStrict() {
        XCTAssertNil(route("myapp://club"))
        XCTAssertNil(route("myapp://club/42/extra"))
        XCTAssertNil(route("myapp://home/extra"))
    }

    func testOptionalTrailingSegmentUsesTwoTemplates() {
        XCTAssertEqual(route("myapp://friends"), .friends(nil))
        XCTAssertEqual(route("myapp://friends/7"), .friends("7"))
    }

    func testIntPlaceholderRejectsNonNumbers() {
        XCTAssertEqual(route("myapp://profile/12"), .profile(12))
        XCTAssertNil(route("myapp://profile/abc"))
    }

    func testPathPlaceholderTakesRemainingSegments() {
        XCTAssertEqual(route("myapp://web/a/b/c"), .web("a/b/c"))
    }

    func testDuplicateOrValuelessQueryIsRejected() {
        XCTAssertNil(route("myapp://room/1?entry=circle&entry=lounge"))
        XCTAssertNil(route("myapp://club/1?flag"))
    }

    func testUnknownEnumQueryFallsBackInsideModuleParse() {
        XCTAssertEqual(route("myapp://room/1?entry=lounge"), .room("1", entry: "lounge"))
        XCTAssertEqual(route("myapp://room/1?entry=unknown"), .room("1", entry: "notification"))
        XCTAssertEqual(route("myapp://room/1"), .room("1", entry: "notification"))
    }

    func testParseRejectionMeansNoMatch() {
        XCTAssertEqual(route("myapp://chat/s1?type=team"), .chat("s1", type: "team"))
        XCTAssertNil(route("myapp://chat/s1?type=unknown"))
        XCTAssertNil(route("myapp://chat/s1"))
    }

    func testMoreSpecificTemplateWinsRegardlessOfOrder() throws {
        var builder = TestRegistry.Builder()
        builder.url("club/<id>", parse: { $0["id"].map(TestRoute.club) }, print: { _ in nil })
        builder.url("club/new", parse: { _ in .home }, print: { _ in nil })
        let registry = try builder.build(requireExhaustive: false)
        XCTAssertEqual(registry.route(for: url("myapp://club/new"), configuration: testConfiguration), .home)
        XCTAssertEqual(registry.route(for: url("myapp://club/9"), configuration: testConfiguration), .club("9"))
    }

    // MARK: - Round trip

    func testEveryReferenceRouteRoundTrips() throws {
        let routes: [TestRoute] = [
            .home, .club("42"), .room("7", entry: "circle"), .chat("s1", type: "peer"),
            .profile(3), .friends(nil), .friends("9"), .web("a/b")
        ]
        for original in routes {
            let custom = try XCTUnwrap(registry.url(for: original, configuration: testConfiguration), "\(original)")
            XCTAssertEqual(registry.route(for: custom, configuration: testConfiguration), original, custom.absoluteString)
            let link = try XCTUnwrap(
                registry.url(for: original, configuration: testConfiguration, universalLinkHost: "app.example.com")
            )
            XCTAssertEqual(registry.route(for: link, configuration: testConfiguration), original, link.absoluteString)
        }
        XCTAssertNil(registry.url(for: .wallet, configuration: testConfiguration), "没有模板的路由不能生成 URL")
        XCTAssertNil(registry.url(for: .home, configuration: testConfiguration, universalLinkHost: "evil.example.com"))
    }

    // MARK: - Rewrite

    func testRewriteReplacesExactTemplateOnly() {
        let rewrite = LYRouteRewrite(replacements: [.init(from: "group/<id>", to: "club/<id>")])
        XCTAssertEqual(route("myapp://group/5", rewrite: rewrite), .club("5"))
        XCTAssertNil(route("myapp://group/5/members", rewrite: rewrite))
        XCTAssertNil(route("myapp://groups/5", rewrite: rewrite))
    }

    func testRewriteSkipsInvalidRulesAndReportsThem() {
        let rewrite = LYRouteRewrite(replacements: [
            .init(from: "a/<x>", to: "b/<y>"),
            .init(from: "c/<id>", to: "club/<id>")
        ])
        let compiled = rewrite.compiled()
        XCTAssertEqual(compiled.rules.count, 1)
        XCTAssertEqual(compiled.invalid, [.init(from: "a/<x>", to: "b/<y>")])
        XCTAssertEqual(route("myapp://c/1", rewrite: rewrite), .club("1"))
    }

    func testRewriteDisablesByKindName() throws {
        let rewrite = try JSONDecoder().decode(LYRouteRewrite.self, from: Data(#"{"disabledKinds":["club"],"replacements":[]}"#.utf8))
        XCTAssertTrue(rewrite.isDisabled(TestRoute.Kind.club))
        XCTAssertFalse(rewrite.isDisabled(TestRoute.Kind.home))
    }
}
