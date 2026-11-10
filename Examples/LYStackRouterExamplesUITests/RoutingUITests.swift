import XCTest

/// 在真实 App 中走一遍示例场景：复用、交互返回、等待、拦截、跨模块、会话型页面、抢占与降级。
@MainActor
final class RoutingUITests: XCTestCase {
    // MARK: - Properties

    private var app: XCUIApplication!

    // MARK: - Lifecycle

    override func setUp() async throws {
        continueAfterFailure = false
    }

    // MARK: - Assembly and Reuse

    func testLoopReusesExistingPagesWithDiscoveredModules() {
        launch(assembly: "discovered")
        assertLoopReusesExistingPages()
    }

    func testLoopReusesExistingPagesWithExplicitModules() {
        launch(assembly: "explicit")
        assertLoopReusesExistingPages()
    }

    // MARK: - Interactive Pop

    func testInteractivePopCancelKeepsPageAndWakesDeferredDeepLink() {
        launch()
        tap("home.club.A")
        tap("open.member.m1")
        waitFor(page("member.m1"))

        // 先安排 6 秒后的深链，再回首页按住返回手势，让深链在交互转场期间到达。
        app.tabBars.buttons["我的"].tap()
        tap("me.delayedDeepLink")
        app.tabBars.buttons["首页"].tap()
        waitFor(page("member.m1"))
        let window = app.windows.firstMatch
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
        let middle = window.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: middle, withVelocity: .slow, thenHoldForDuration: 8)

        // 手势取消：成员页仍在栈顶，路由器没有清理它；转场期间到达的深链先等待，取消后再打开。
        waitFor(page("club.77"), timeout: 5)
        let events = status("club.77").value as? String ?? ""
        XCTAssertTrue(events.contains("club: deferred | club: created"), events)
        tapBack()
        waitFor(page("member.m1"))
        XCTAssertTrue(status("member.m1").label.contains("depth 3 · cleaned 0"), status("member.m1").label)
    }

    func testCompletedSwipeBackIsNotTreatedAsRouterCleanup() {
        launch()
        tap("home.club.A")
        tap("open.member.m1")
        waitFor(page("member.m1"))
        let window = app.windows.firstMatch
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        waitFor(page("club.A"))
        XCTAssertTrue(status("club.A").label.contains("depth 2 · cleaned 0"), status("club.A").label)
        tap("open.member.m1")
        waitFor(page("member.m1"))
    }

    // MARK: - External Requests

    func testDeepLinkWaitsForSheetDismissal() {
        launch()
        app.tabBars.buttons["我的"].tap()
        tap("me.sheetDeepLink")
        waitFor(page("sheet"))
        waitForLabel(status("sheet"), containing: "club: deferred")
        tap("sheet.close")
        waitFor(page("club.99"))
    }

    func testCustomSchemeAndUniversalLinkOpenRegisteredTemplates() {
        launch()
        tap("home.url.club")
        waitFor(page("club.42"))
        tapBack()
        tap("home.url.chat")
        waitFor(page("chat.c2"))
        XCTAssertTrue(app.tabBars.buttons["消息"].isSelected)
    }

    // MARK: - Interceptors

    func testWalletRedirectsToLoginThenOpensAfterSignIn() {
        launch()
        app.tabBars.buttons["我的"].tap()
        tap("me.wallet")
        waitFor(page("login"))
        tap("login.signIn")
        waitFor(app.staticTexts["已登录"])
        tap("me.wallet")
        waitFor(page("wallet"))
    }

    // MARK: - Cross Module and Session Pages

    func testCrossModuleChatIsEmbeddedByHostHook() {
        launch()
        tap("home.club.A")
        tap("open.chat.owner")
        waitFor(page("chat.owner-A"))
        XCTAssertTrue(app.tabBars.buttons["消息"].isSelected)
        XCTAssertTrue(page("conversations").exists, "私信嵌入会话容器，没有被 push")

        tap("open.chat.c1")
        waitFor(page("chat.c1"))
        XCTAssertFalse(page("chat.owner-A").exists)
        tap("open.chat.c1")
        waitForLabel(status("conversations"), containing: "chat: alreadyVisible")
        XCTAssertTrue(status("conversations").label.contains("cleaned 1"), status("conversations").label)
    }

    func testRoomIsRevealedAcrossTabsAndSwitchingRoomsAsksFirst() {
        launch()
        tap("home.club.A")
        tap("open.room.r1")
        waitFor(page("room.r1"))

        app.tabBars.buttons["消息"].tap()
        tap("open.chat.c1")
        tap("chat.open.room.r1")
        waitFor(page("room.r1"))
        XCTAssertTrue(app.tabBars.buttons["首页"].isSelected)

        tap("open.room.r2")
        app.alerts.buttons["留下"].tap()
        waitFor(page("room.r1"))
        tap("open.room.r2")
        app.alerts.buttons["离开并进入"].tap()
        waitFor(page("room.r2"))
        XCTAssertTrue(status("room.r2").label.contains("depth 3"), status("room.r2").label)
    }

    // MARK: - Preemption and Fallback

    func testBackDuringPreparationPreemptsSlowPage() {
        launch()
        tap("home.club.A")
        tap("open.slowClub.S")
        tapBack()
        waitFor(page("home"))
        waitForLabel(status("home"), containing: "slowClub: failed.contextChanged")
        sleep(2)
        XCTAssertFalse(page("club.S").exists, "被抢占的准备不会再展示页面")
    }

    func testDegradedRouteFallsBackToPlaceholder() {
        launch()
        app.tabBars.buttons["我的"].tap()
        tap("me.degrade")
        tap("open.member.m1")
        waitFor(app.staticTexts["LYRoutePlaceholder"])
        tapBack()
        tap("me.degrade")
        tap("open.member.m1")
        waitFor(page("member.m1"))
    }

    // MARK: - Private

    private func launch(assembly: String = "discovered") {
        app = XCUIApplication()
        app.launchArguments = ["-assembly", assembly]
        app.launch()
        waitFor(page("home"))
    }

    private func assertLoopReusesExistingPages() {
        app.tabBars.buttons["我的"].tap()
        waitForLabel(app.staticTexts["me.assembly"], containing: "account,community,messages")
        app.tabBars.buttons["首页"].tap()
        tap("home.club.A")
        tap("open.member.m1")
        tap("open.club.B")
        tap("open.member.m1")
        waitFor(page("member.m1"))
        XCTAssertTrue(status("member.m1").label.contains("depth 3 · cleaned 1"), status("member.m1").label)
        tap("open.club.A")
        waitFor(page("club.A"))
        waitForLabel(status("club.A"), containing: "depth 2 · cleaned 2 · last club: reused")
    }

    private func page(_ id: String) -> XCUIElement {
        app.staticTexts["page.\(id)"]
    }

    private func status(_ id: String) -> XCUIElement {
        app.staticTexts["status.\(id)"]
    }

    private func tap(_ id: String) {
        let button = app.buttons[id].firstMatch
        waitFor(button)
        let hittable = expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: button)
        wait(for: [hittable], timeout: 5)
        button.tap()
    }

    private func tapBack() {
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "等待元素超时：\(element)")
    }

    private func waitForLabel(_ element: XCUIElement, containing text: String) {
        let predicate = NSPredicate(format: "label CONTAINS %@", text)
        let matched = expectation(for: predicate, evaluatedWith: element)
        wait(for: [matched], timeout: 5)
    }
}
