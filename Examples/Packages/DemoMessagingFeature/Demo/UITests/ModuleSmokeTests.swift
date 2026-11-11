import XCTest

@MainActor
final class ModuleSmokeTests: XCTestCase {
    func testIndependentModuleOpensItsPage() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["module.open"].waitForExistence(timeout: 5))
        app.buttons["module.open"].tap()
        XCTAssertTrue(app.staticTexts["page.chat.c1"].waitForExistence(timeout: 5))
    }

    func testMissingModuleUsesExplicitFallback() {
        let app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.buttons["module.fallback"].waitForExistence(timeout: 5))
        app.buttons["module.fallback"].tap()
        XCTAssertTrue(app.staticTexts["LYRoutePlaceholder"].waitForExistence(timeout: 5))
    }
}
