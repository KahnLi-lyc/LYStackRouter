#if canImport(UIKit)
    import UIKit
    import XCTest
    @testable import LYStackRouter

    /// 控制转场完成通知，验证页面实际归属与导航容器生命周期独立变化时的清理。
    @MainActor
    final class TransitionRemovalTests: XCTestCase {
        func testCompletionCleansDetachedPageAfterNavigationDeallocates() throws {
            let page = TestPage(.club("removed"))
            let transition = RemovalTransition()
            var host: WeakCleanupHost?
            var router: LYStackRouter<AppRoute>?
            weak var releasedNavigation: UINavigationController?
            try autoreleasepool {
                let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
                navigation.pushViewController(page, animated: false)
                navigation.manualTransition = transition
                releasedNavigation = navigation
                let owner = WeakCleanupHost(navigation: navigation)
                host = owner
                let createdRouter = try makeRouter(host: owner)
                router = createdRouter
                try createdRouter.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
                XCTAssertEqual(page.removedCount, 0)
                XCTAssertFalse(createdRouter.transitionRemovals.isEmpty)
            }
            let testedRouter = try XCTUnwrap(router)
            defer { testedRouter.tearDown() }
            XCTAssertNil(releasedNavigation)

            withExtendedLifetime(host) { transition.finish() }
            XCTAssertEqual(page.removedCount, 1)
            XCTAssertTrue(testedRouter.transitionRemovals.isEmpty)
            transition.finish()
            XCTAssertEqual(page.removedCount, 1)
        }

        func testCompletionSkipsPageReparentedToAnotherNavigationStack() throws {
            let page = TestPage(.club("moved"))
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            navigation.pushViewController(page, animated: false)
            let transition = RemovalTransition()
            navigation.manualTransition = transition
            let host = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
            let destination = UINavigationController(rootViewController: page)

            transition.finish()
            XCTAssertEqual(page.removedCount, 0)
            XCTAssertTrue(page.parent === destination)
            XCTAssertTrue(router.transitionRemovals.isEmpty)
        }

        func testCompletionSkipsPageReusedAsVisibleWindowRoot() throws {
            let page = TestPage(.club("window-root"))
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            navigation.pushViewController(page, animated: false)
            let transition = RemovalTransition()
            navigation.manualTransition = transition
            let host = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
            window.rootViewController = page
            window.addSubview(page.view)
            XCTAssertNotNil(page.view.window)

            transition.finish()
            XCTAssertEqual(page.removedCount, 0)
            XCTAssertTrue(router.transitionRemovals.isEmpty)
            window.rootViewController = nil
        }

        func testInvalidationSkipsPageReusedAsVisibleWindowRoot() throws {
            let page = TestPage(.club("window-root"))
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            navigation.pushViewController(page, animated: false)
            let transition = RemovalTransition()
            navigation.manualTransition = transition
            let host = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 500))
            window.rootViewController = page
            window.addSubview(page.view)
            XCTAssertNotNil(page.view.window)

            router.resetSession()
            XCTAssertEqual(page.removedCount, 0)
            transition.finish()
            XCTAssertEqual(page.removedCount, 0)
            XCTAssertTrue(router.transitionRemovals.isEmpty)
            window.rootViewController = nil
        }

        func testInvalidationSkipsPagePresentedByAnotherController() throws {
            let page = PresentedRemovalPage()
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            navigation.pushViewController(page, animated: false)
            let transition = RemovalTransition()
            navigation.manualTransition = transition
            let host = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
            page.presentationOwner = UIViewController()

            router.resetSession()
            XCTAssertEqual(page.removedCount, 0)
            transition.finish()
            XCTAssertEqual(page.removedCount, 0)
            XCTAssertTrue(router.transitionRemovals.isEmpty)
        }

        func testInvalidationReleasesParentedSnapshotsWhenCompletionNeverArrives() throws {
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            let transition = RemovalTransition()
            let host = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            weak var releasedPage: TestPage?
            try autoreleasepool {
                var page: TestPage? = TestPage(.club("reparented"))
                releasedPage = page
                try navigation.pushViewController(XCTUnwrap(page), animated: false)
                navigation.manualTransition = transition
                try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
                let destination = UIViewController()
                try destination.addChild(XCTUnwrap(page))
                page?.didMove(toParent: destination)

                router.resetSession()
                XCTAssertEqual(page?.removedCount, 0)
                page?.willMove(toParent: nil)
                page?.removeFromParent()
                page = nil
            }
            XCTAssertNil(releasedPage, "失效操作不能依赖可能缺失的 UIKit 完成通知来释放页面")
            XCTAssertTrue(router.transitionRemovals.isEmpty)
        }

        func testInvalidationAndLateCompletionCleanDetachedPageOnlyOnce() throws {
            let page = TestPage(.club("detached"))
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            navigation.pushViewController(page, animated: false)
            let transition = RemovalTransition()
            navigation.manualTransition = transition
            let host = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)

            router.resetSession()
            XCTAssertEqual(page.removedCount, 1)
            transition.finish()
            XCTAssertEqual(page.removedCount, 1)
        }

        func testLateCompletionAfterInvalidationCleansNewlyDetachedSurvivingPage() throws {
            let page = TestPage(.club("late-detached"))
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            navigation.pushViewController(page, animated: false)
            let transition = RemovalTransition()
            navigation.manualTransition = transition
            let host = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: host)
            defer { router.tearDown() }
            try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
            let destination = UIViewController()
            destination.addChild(page)
            page.didMove(toParent: destination)

            router.resetSession()
            XCTAssertEqual(page.removedCount, 0)
            XCTAssertTrue(router.transitionRemovals.isEmpty)
            page.willMove(toParent: nil)
            page.removeFromParent()
            transition.finish()
            XCTAssertEqual(page.removedCount, 1)
        }

        func testCompletionStillNotifiesPageLifecycleAfterOriginalHostDeallocates() throws {
            let page = TestPage(.club("released-owner"))
            let navigation = DeferredCleanupNavigation(rootViewController: UIViewController())
            navigation.pushViewController(page, animated: false)
            let transition = RemovalTransition()
            navigation.manualTransition = transition
            var host: WeakCleanupHost? = WeakCleanupHost(navigation: navigation)
            let router = try makeRouter(host: XCTUnwrap(host))
            defer { router.tearDown() }
            try router.replaceStack([XCTUnwrap(navigation.viewControllers.first)], in: navigation, animated: false)
            weak var releasedHost: WeakCleanupHost?
            releasedHost = host
            host = nil
            XCTAssertNil(releasedHost)

            transition.finish()
            XCTAssertEqual(page.removedCount, 1)
            XCTAssertTrue(router.transitionRemovals.isEmpty)
        }

        private func makeRouter(host: WeakCleanupHost) throws -> LYStackRouter<AppRoute> {
            try LYStackRouter<AppRoute>.build(host: host, modules: .explicit([]), allowsUnregistered: true)
        }
    }

    @MainActor
    private final class PresentedRemovalPage: UIViewController, LYRoutePageLifecycle {
        var presentationOwner: UIViewController?
        private(set) var removedCount = 0
        override var presentingViewController: UIViewController? {
            presentationOwner ?? super.presentingViewController
        }

        func routerDidRemovePage() {
            removedCount += 1
        }
    }

    @MainActor
    private final class WeakCleanupHost: LYRouterHost {
        weak var activeNavigationController: UINavigationController?
        var routerSessionID: String? {
            nil
        }

        var isRouterReady: Bool {
            true
        }

        var routerRootViewController: UIViewController? {
            activeNavigationController
        }

        init(navigation: UINavigationController) {
            activeNavigationController = navigation
        }
    }

    @MainActor
    private final class DeferredCleanupNavigation: UINavigationController {
        var manualTransition: RemovalTransition?
        override var transitionCoordinator: (any UIViewControllerTransitionCoordinator)? {
            manualTransition
        }

        override func setViewControllers(_ viewControllers: [UIViewController], animated: Bool) {
            let transition = manualTransition
            manualTransition = nil
            super.setViewControllers(viewControllers, animated: false)
            manualTransition = transition
        }
    }

    @MainActor
    private final class RemovalTransition: NSObject, UIViewControllerTransitionCoordinator {
        private var completions: [(any UIViewControllerTransitionCoordinatorContext) -> Void] = []
        let isAnimated = true
        let presentationStyle = UIModalPresentationStyle.none
        let initiallyInteractive = false
        let isInterruptible = false
        let isInteractive = false
        let isCancelled = false
        let transitionDuration: TimeInterval = 0.3
        let percentComplete: CGFloat = 0
        let completionVelocity: CGFloat = 0
        let completionCurve = UIView.AnimationCurve.linear
        let containerView = UIView()
        let targetTransform = CGAffineTransform.identity

        func animate(alongsideTransition animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                     completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool {
            animation?(self)
            if let completion { completions.append(completion) }
            return true
        }

        func animateAlongsideTransition(in view: UIView?, animation: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?,
                                        completion: ((any UIViewControllerTransitionCoordinatorContext) -> Void)?) -> Bool {
            animate(alongsideTransition: animation, completion: completion)
        }

        func notifyWhenInteractionEnds(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {}
        func notifyWhenInteractionChanges(_ handler: @escaping (any UIViewControllerTransitionCoordinatorContext) -> Void) {}
        func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
            nil
        }

        func view(forKey key: UITransitionContextViewKey) -> UIView? {
            nil
        }

        func finish() {
            let callbacks = completions
            completions.removeAll()
            callbacks.forEach { $0(self) }
        }
    }
#endif
