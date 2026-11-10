import XCTest
@testable import LYStackRouterCore

final class URLTemplateTests: XCTestCase {
    func testInvalidTemplatesAreRejected() {
        for raw in ["", "/", "a/<>", "a/<bad:name>", "a/<x>/<x>", "a/<path:x>/b", "a/b<x>", "a/<na-me>"] {
            XCTAssertThrowsError(try LYURLTemplate(raw), raw)
        }
    }

    func testShapeKeyIgnoresPlaceholderNamesButKeepsTypesOfTail() throws {
        XCTAssertEqual(try LYURLTemplate("a/<x>").shapeKey, try LYURLTemplate("a/<int:y>").shapeKey)
        XCTAssertNotEqual(try LYURLTemplate("a/<x>").shapeKey, try LYURLTemplate("a/<path:x>").shapeKey)
        XCTAssertEqual(try LYURLTemplate("/a/b/").literalCount, 2)
    }

    func testRenderRejectsMissingOrInvalidValues() throws {
        let template = try LYURLTemplate("user/<int:id>/<name>")
        XCTAssertEqual(template.render(["id": "3", "name": "kahn"]), ["user", "3", "kahn"])
        XCTAssertNil(template.render(["id": "x", "name": "kahn"]))
        XCTAssertNil(template.render(["id": "3"]))
        XCTAssertNil(template.render(["id": "3", "name": "a/b"]))
    }
}
