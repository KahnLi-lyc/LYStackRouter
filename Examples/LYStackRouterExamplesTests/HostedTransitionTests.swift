import UIKit
import XCTest
@testable import LYStackRouter

/// 在真实窗口中验证转场、弹窗关闭唤醒与确认门；包内测试没有窗口，覆盖不到这些路径。
@MainActor
final class HostedTransitionTests: XCTestCase {
    private var gate: Gate!
    private var host: LYTabBarHost!
    private var router: LYStackRouter<AppRoute>!
    private var window: UIWindow!

    override func setUp() async throws {
        gate = Gate()
        host = makeTabHost()
        router = try LYStackRouter<AppRoute>.build(
            host: host,
            modules: .explicit([CommunityModule.self, ChatModule.self]),
            environment: makeEnvironment(gate: gate)
        )
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        window = UIWindow(windowScene: scene)
        window.rootViewController = host.tabBarController
        window.makeKeyAndVisible()
        // 宿主 App 刚启动时可能尚未进入前台活跃状态，此时 UIKit 会推迟带动画的栈操作。
        await waitUntil {
            UIApplication.shared.applicationState == .active
                && self.host.tabBarController.viewIfLoaded?.window != nil && self.isIdle
        }
    }

    override func tearDown() async throws {
        gate.open()
        router.tearDown()
        window.isHidden = true
        window.rootViewController = nil
    }

    private var home: UINavigationController {
        host.allNavigationControllers[0]
    }

    private var isIdle: Bool {
        home.transitionCoordinator == nil && host.tabBarController.transitionCoordinator == nil
    }

    // MARK: - Transitions

    func testAnimatedReuseCleansRemovedPagesOnlyAfterTransition() async throws {
        let created = await router.open(.club("x"))
        XCTAssertEqual(created, .created)
        _ = await router.open(.profile("a"))
        let middle = try XCTUnwrap(home.topViewController as? TestPage)
        _ = await router.open(.club("y"))
        let top = try XCTUnwrap(home.topViewController as? TestPage)

        XCTAssertEqual(router.request(.club("x")), .reused)
        XCTAssertNotNil(home.transitionCoordinator, "窗口中的回退带转场")
        XCTAssertEqual(middle.removedCount + top.removedCount, 0, "转场结束前不清理")
        let settled = await router.waitForNavigation()
        XCTAssertEqual(settled, .reused)
        XCTAssertEqual(middle.removedCount, 1)
        XCTAssertEqual(top.removedCount, 1)
        XCTAssertEqual(home.viewControllers.count, 2)
    }

    func testUserTapDuringAnimatedPushIsIgnored() async {
        XCTAssertEqual(router.request(.club("x")), .created)
        XCTAssertTrue(router.isNavigating, "动画 push 期间执行仍在进行")
        XCTAssertEqual(router.request(.club("y")), .ignored)
        await router.waitForNavigation()
        XCTAssertEqual(home.viewControllers.count, 2)
    }

    func testBackPreemptsPreparationInWindow() async throws {
        _ = await router.open(.club("x"))
        let source = try XCTUnwrap(home.topViewController)
        let opening = Task { await router.open(.slowChat("s1")) }
        await waitUntil { self.gate.waiting == 1 }
        router.navigateBack(from: source, in: home)
        let preempted = await opening.value
        XCTAssertEqual(preempted, .failed(.contextChanged))
        await router.waitForNavigation()
        gate.open()
        await waitUntil { self.isIdle }
        XCTAssertEqual(home.viewControllers.count, 1)
    }

    // MARK: - Modal

    func testExternalRequestWaitsForSheetDismissal() async {
        let sheet = UIViewController()
        await withCheckedContinuation { continuation in
            home.present(sheet, animated: true) { continuation.resume() }
        }
        let deferred = await router.open(.club("x"), source: .deepLink)
        XCTAssertEqual(deferred, .deferred)
        await withCheckedContinuation { continuation in
            sheet.dismiss(animated: true) { continuation.resume() }
        }
        await waitUntil { self.home.viewControllers.count == 2 }
        XCTAssertEqual((home.topViewController as? TestPage)?.identity, .club("x"))
    }

    // MARK: - Confirmation

    func testRealAlertConfirmationRunsOnConfirmOnce() async throws {
        var confirm: (@MainActor () -> Void)?
        let defaultPresenter = router.confirmationPresenter
        router.confirmationPresenter = { alert, navigation, confirmAction, onPresented in
            confirm = confirmAction
            return defaultPresenter(alert, navigation, confirmAction, onPresented)
        }
        var confirmed = 0
        let result = router.performUserNavigation(route: .settings, source: .user) { context in
            context.confirm(title: "确认", message: nil, confirmTitle: "确定", cancelTitle: "取消") { context in
                confirmed += 1
                context.show { TestPage(nil, title: "confirmed") }
            }
        }
        XCTAssertEqual(result, .awaitingConfirmation)
        await waitUntil { !self.router.isNavigating }
        XCTAssertTrue(home.presentedViewController is UIAlertController, "确认框真实展示后才结算")
        let action = try XCTUnwrap(confirm)
        action()
        action()
        await waitUntil { self.home.viewControllers.count == 2 && self.isIdle }
        XCTAssertEqual(confirmed, 1)
        XCTAssertNil(home.presentedViewController)
    }

    func testCancelledConfirmationDoesNothing() async throws {
        let result = router.performUserNavigation(route: .settings, source: .user) { context in
            context.confirm(title: "确认", message: nil, confirmTitle: "确定", cancelTitle: "取消") { _ in
                XCTFail("取消后不应继续")
            }
        }
        XCTAssertEqual(result, .awaitingConfirmation)
        await waitUntil { !self.router.isNavigating }
        let alert = try XCTUnwrap(home.presentedViewController as? UIAlertController)
        await withCheckedContinuation { continuation in
            alert.dismiss(animated: true) { continuation.resume() }
        }
        XCTAssertEqual(router.request(.club("x")), .created)
    }

    // MARK: - Helpers

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "等待条件超时")
    }
}
