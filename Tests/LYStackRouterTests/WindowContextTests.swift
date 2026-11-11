#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    @MainActor
    final class WindowContextTests: XCTestCase {
        func testMainWindowPrefersVisibleNormalKeyWindowOverOverlay() {
            let normal = WindowCandidate()
            normal.rootViewController = UIViewController()
            normal.isHidden = false
            normal.key = true
            let overlay = WindowCandidate()
            overlay.rootViewController = UIViewController()
            overlay.isHidden = false
            overlay.windowLevel = .alert
            overlay.key = true
            XCTAssertTrue(LYWindowContext.resolvedMainWindow(in: [overlay, normal]) === normal)
        }

        func testMainWindowRejectsAmbiguousHiddenAndRootlessWindows() {
            let first = WindowCandidate()
            first.rootViewController = UIViewController()
            first.isHidden = false
            let second = WindowCandidate()
            second.rootViewController = UIViewController()
            second.isHidden = false
            XCTAssertNil(LYWindowContext.resolvedMainWindow(in: [first, second]))
            second.isHidden = true
            XCTAssertTrue(LYWindowContext.resolvedMainWindow(in: [first, second]) === first)
            first.rootViewController = nil
            XCTAssertNil(LYWindowContext.resolvedMainWindow(in: [first, second]))
        }

        func testTopControllerDescendsSelectedNavigationStack() {
            let hidden = UIViewController()
            let visible = UIViewController()
            let navigation = UINavigationController(rootViewController: visible)
            let tabs = UITabBarController()
            tabs.viewControllers = [hidden, navigation]
            tabs.selectedIndex = 1
            XCTAssertTrue(LYWindowContext.topViewController(from: tabs) === visible)
        }

        func testPresentationTakesPrecedenceOverContainerContents() {
            let root = PresentedNavigation(rootViewController: UIViewController())
            let modalPage = UIViewController()
            root.presentation = UINavigationController(rootViewController: modalPage)
            XCTAssertTrue(LYWindowContext.topViewController(from: root) === modalPage)
        }

        func testEmptyContainersAndInactiveSearchStopAtContainer() {
            let navigation = UINavigationController()
            XCTAssertTrue(LYWindowContext.topViewController(from: navigation) === navigation)
            let search = UISearchController(searchResultsController: UIViewController())
            XCTAssertTrue(LYWindowContext.topViewController(from: search) === search)
            XCTAssertNil(LYWindowContext.topViewController(from: nil))
        }

        func testSearchDescendsOnlyWhenActiveResultsAreMounted() {
            let results = UIViewController()
            let search = ActiveSearch(searchResultsController: results)
            XCTAssertTrue(LYWindowContext.topViewController(from: search) === search)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
            window.addSubview(results.view)
            XCTAssertTrue(LYWindowContext.topViewController(from: search) === results)
        }

        func testPresentationCycleTerminates() {
            let first = PresentedNavigation()
            let second = PresentedNavigation()
            first.presentation = second
            second.presentation = first
            XCTAssertTrue(LYWindowContext.topViewController(from: first) === second)
            first.presentation = nil
            second.presentation = nil
        }

        func testBoundsPreferValidWindowThenSceneThenScreen() {
            let window = CGRect(x: 0, y: 0, width: 300, height: 400)
            let scene = CGRect(x: 0, y: 0, width: 500, height: 600)
            let screen = CGRect(x: 0, y: 0, width: 700, height: 800)
            XCTAssertEqual(LYWindowContext.resolvedBounds(window: window, scene: scene, screen: screen), window)
            XCTAssertEqual(LYWindowContext.resolvedBounds(window: .zero, scene: scene, screen: screen), scene)
            XCTAssertEqual(LYWindowContext.resolvedBounds(window: .null, scene: .infinite, screen: screen), screen)
            XCTAssertEqual(LYWindowContext.resolvedBounds(window: nil, scene: nil, screen: nil), .zero)
            let invalid = CGRect(x: 0, y: 0, width: CGFloat.nan, height: 10)
            XCTAssertEqual(LYWindowContext.resolvedBounds(window: invalid, scene: nil, screen: .zero), .zero)
        }

        func testContainerBoundsUseViewBeforeWindowAndDoNotGuessAnotherScene() {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 123, height: 456))
            XCTAssertEqual(LYWindowContext.containerBounds(for: view), view.bounds)
            view.bounds = .zero
            XCTAssertEqual(LYWindowContext.containerBounds(for: view), .zero)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 300, height: 500))
            window.addSubview(view)
            XCTAssertEqual(LYWindowContext.containerBounds(for: view), window.bounds)
        }
    }

    @MainActor
    private final class ActiveSearch: UISearchController {
        override var isActive: Bool {
            get { true }
            set {}
        }
    }

    @MainActor
    private final class WindowCandidate: UIWindow {
        var key = false
        override var isKeyWindow: Bool {
            key
        }
    }

    @MainActor
    private final class PresentedNavigation: UINavigationController {
        var presentation: UIViewController?
        override var presentedViewController: UIViewController? {
            presentation
        }
    }
#endif
