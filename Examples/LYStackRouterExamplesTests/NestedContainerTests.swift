import DemoMessagingFeature
import DemoRouteContract
import DemoUIKit
import LYStackRouter
import UIKit
import XCTest
@testable import LYStackRouterExamples

@MainActor
final class NestedContainerTests: XCTestCase {
    func testHostDeclaresDetailStackAndRevealsItsOwningTab() {
        let container = ConversationsViewController(metrics: DemoMetrics())
        let messages = UINavigationController(rootViewController: container)
        let home = UINavigationController(rootViewController: UIViewController())
        let tabs = UITabBarController()
        tabs.viewControllers = [home, messages]
        let host = DemoHost(tabs: LYTabBarHost(tabBarController: tabs, placements: [.home: 0, .messages: 1]))
        XCTAssertEqual(host.navigationDomain(for: .messages), [messages, container.detailNavigation])
        XCTAssertTrue(host.allNavigationControllers.contains { $0 === container.detailNavigation })
        messages.pushViewController(UIViewController(), animated: false)
        host.reveal(container.detailNavigation)
        XCTAssertTrue(tabs.selectedViewController === messages)
        XCTAssertTrue(messages.topViewController === container)
    }

    func testReplacingNestedDetailCleansOnlyRemovedPagesAndKeepsItsRoot() {
        let metrics = DemoMetrics()
        let container = ConversationsViewController(metrics: metrics)
        let first = DemoPage(pageID: "first", title: "first", identity: .chat("first"), metrics: metrics)
        let second = DemoPage(pageID: "second", title: "second", identity: .chat("second"), metrics: metrics)
        XCTAssertEqual(container.showDetail(identity: DemoPageIdentity.chat("first"), animated: false) { first }, .created)
        XCTAssertEqual(container.showDetail(identity: DemoPageIdentity.chat("first"), animated: false) {
            XCTFail("不能重复构造")
            return first
        }, .alreadyVisible)
        XCTAssertEqual(metrics.cleanedPages, 0)
        XCTAssertEqual(container.showDetail(identity: DemoPageIdentity.chat("second"), animated: false) { second }, .created)
        XCTAssertEqual(container.detailNavigation.viewControllers, [second])
        XCTAssertEqual(metrics.cleanedPages, 1)
        first.routerDidRemovePage()
        XCTAssertEqual(metrics.cleanedPages, 1, "页面清理幂等")
    }
}
