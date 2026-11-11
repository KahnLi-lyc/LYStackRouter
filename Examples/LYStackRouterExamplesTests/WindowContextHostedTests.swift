import UIKit
import XCTest
@testable import LYStackRouter

/// 真实场景与窗口中的 `LYWindowContext`：normal 主窗口优先于浮层 key window，顶层控制器按展示、导航、Tab 顺序展开。
@MainActor
final class WindowContextHostedTests: XCTestCase {
    // MARK: - Properties

    private var scene: UIWindowScene!
    private var window: UIWindow!
    private var overlay: UIWindow?
    private var hiddenWindows: [UIWindow] = []

    // MARK: - Lifecycle

    override func setUp() async throws {
        scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        // 隐藏示例 App 自己的 normal 窗口，使本用例的窗口成为唯一候选；结束后恢复。
        hiddenWindows = scene.windows.filter { $0.windowLevel == .normal && !$0.isHidden }
        hiddenWindows.forEach { $0.isHidden = true }
        window = UIWindow(windowScene: scene)
        window.makeKeyAndVisible()
    }

    override func tearDown() async throws {
        if let presented = window.rootViewController?.presentedViewController {
            await withCheckedContinuation { continuation in
                presented.dismiss(animated: false) { continuation.resume() }
            }
        }
        overlay?.isHidden = true
        overlay = nil
        window.isHidden = true
        window.rootViewController = nil
        hiddenWindows.forEach { $0.isHidden = false }
        hiddenWindows.first?.makeKey()
    }

    // MARK: - Tests

    /// 浮层窗口成为 key window 时，主窗口仍是可见、有根控制器的 normal 窗口；keyWindow 返回真实的浮层。
    func testMainWindowPrefersNormalWindowWhenOverlayIsKey() {
        window.rootViewController = UIViewController()
        let overlay = UIWindow(windowScene: scene)
        overlay.windowLevel = .alert + 1
        overlay.rootViewController = UIViewController()
        overlay.makeKeyAndVisible()
        self.overlay = overlay

        XCTAssertTrue(LYWindowContext.keyWindow(in: scene) === overlay)
        XCTAssertTrue(LYWindowContext.mainWindow(in: scene) === window)
        XCTAssertTrue(LYWindowContext.topViewController(in: scene) === window.rootViewController)
    }

    /// 顶层控制器依次展开选中 Tab、导航栈与弹出的导航栈。
    func testTopControllerUnwrapsTabNavigationAndPresentation() async {
        let pushed = UIViewController()
        let navigation = UINavigationController(rootViewController: UIViewController())
        navigation.pushViewController(pushed, animated: false)
        let tabs = UITabBarController()
        tabs.viewControllers = [UIViewController(), navigation]
        tabs.selectedIndex = 1
        window.rootViewController = tabs
        XCTAssertTrue(LYWindowContext.topViewController(in: scene) === pushed)

        let modalTop = UIViewController()
        let modal = UINavigationController(rootViewController: modalTop)
        await withCheckedContinuation { continuation in
            tabs.present(modal, animated: false) { continuation.resume() }
        }
        XCTAssertTrue(LYWindowContext.topViewController(in: scene) === modalTop)
        XCTAssertTrue(LYWindowContext.topViewController(in: window) === modalTop)
    }
}
