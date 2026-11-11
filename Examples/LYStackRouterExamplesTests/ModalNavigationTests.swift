import UIKit
import XCTest
@testable import LYStackRouter

/// 使用真实窗口验证模态导航域、准备期抢占、代理转发及退出清理。
@MainActor
final class ModalNavigationTests: XCTestCase {
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
        await waitUntil {
            UIApplication.shared.applicationState == .active
                && self.host.tabBarController.viewIfLoaded?.window != nil
        }
    }

    override func tearDown() async throws {
        gate.open()
        if host.tabBarController.presentedViewController != nil {
            await dismiss(host.tabBarController)
        }
        router.tearDown()
        window.isHidden = true
        window.rootViewController = nil
    }

    func testModalPushAndReuseUseSourceStackAndAnimationOption() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController)
        XCTAssertEqual(router.request(.club("x"), options: .init(animated: false, from: root)), .created)
        let club = try XCTUnwrap(modal.topViewController as? TestPage)
        XCTAssertEqual(router.request(.profile("p"), options: .init(animated: false, from: club)), .created)
        let profile = try XCTUnwrap(modal.topViewController as? TestPage)
        XCTAssertEqual(router.request(.club("x"), options: .init(animated: false, from: profile)), .reused)
        XCTAssertTrue(modal.topViewController === club)
        XCTAssertNil(modal.transitionCoordinator)
        XCTAssertEqual(profile.removedCount, 1)
        XCTAssertEqual(host.allNavigationControllers[0].viewControllers.count, 1)
        XCTAssertEqual(modal.viewControllers.count, 2)
    }

    func testClientPopsModalStackThenDismissesRootAndCleansOnce() async throws {
        let home = host.allNavigationControllers[0]
        let homeClient = router.makeClient(from: home.topViewController)
        let ignored = await homeClient.dismiss(animated: false)
        XCTAssertEqual(ignored, .ignored)
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController as? TestPage)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        let page = try XCTUnwrap(modal.topViewController as? TestPage)
        let popped = await router.makeClient(from: page).dismiss(animated: false)
        XCTAssertEqual(popped, .reused)
        XCTAssertTrue(modal.topViewController === root)
        XCTAssertEqual(page.removedCount, 1)
        let dismissed = await router.makeClient(from: root).dismiss(animated: false)
        XCTAssertEqual(dismissed, .performed)
        await waitUntil { self.router.managedNavigations.isEmpty }
        XCTAssertEqual(root.removedCount, 1)
        router.navigationDidStabilize()
        XCTAssertEqual(root.removedCount, 1)
        XCTAssertEqual(page.removedCount, 1)
    }

    func testSystemBackFinishesBeforeUncooperativePreparationReturns() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        let source = try XCTUnwrap(modal.topViewController)
        var finished: LYOpenResult?
        let opening = Task {
            let result = await router.open(.slowChat("late"), options: .init(animated: false, from: source))
            finished = result
        }
        await waitUntil { self.gate.waiting == 1 }
        modal.popViewController(animated: true)
        await waitUntil { finished != nil }
        XCTAssertEqual(finished, .failed(.contextChanged))
        XCTAssertFalse(router.isNavigating)
        gate.open()
        await opening.value
        await waitUntil { modal.transitionCoordinator == nil }
        XCTAssertEqual(modal.viewControllers.count, 1)
    }

    func testDismissalFinishesPreparationAndRejectsLatePresentation() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController as? TestPage)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        let source = try XCTUnwrap(modal.topViewController as? TestPage)
        var finished: LYOpenResult?
        let opening = Task {
            finished = await router.open(.slowChat("late"), options: .init(animated: false, from: source))
        }
        await waitUntil { self.gate.waiting == 1 }
        await dismiss(modal)
        await waitUntil { finished != nil && self.router.managedNavigations.isEmpty }
        XCTAssertEqual(finished, .failed(.contextChanged))
        XCTAssertEqual(root.removedCount, 0, "业务自行关闭不属于路由清理")
        XCTAssertEqual(source.removedCount, 0)
        gate.open()
        await opening.value
        XCTAssertEqual(modal.viewControllers.count, 2)
        XCTAssertEqual(host.allNavigationControllers[0].viewControllers.count, 1)
    }

    func testOriginalDelegateReceivesOptionalTransitionsAndIsRestored() async throws {
        let delegate = ModalDelegate()
        let modal = await presentModal(delegate: delegate)
        let root = try XCTUnwrap(modal.topViewController)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        let proxy = try XCTUnwrap(modal.delegate)
        XCTAssertFalse(proxy === delegate)
        let selector = NSSelectorFromString("navigationController:animationControllerForOperation:fromViewController:toViewController:")
        XCTAssertTrue(proxy.responds(to: selector))
        let requestsBefore = delegate.animationRequests
        let animation = proxy.navigationController?(modal, animationControllerFor: .push, from: root, to: UIViewController())
        XCTAssertTrue(animation === delegate.animator)
        XCTAssertEqual(delegate.animationRequests, requestsBefore + 1)
        XCTAssertGreaterThan(delegate.didShowCount, 0)
        await dismiss(modal)
        await waitUntil { self.router.managedNavigations.isEmpty }
        XCTAssertTrue(modal.delegate === delegate)
    }

    func testCancelledInteractivePopPreservesPreparingExecution() async throws {
        let delegate = ModalDelegate()
        let modal = await presentModal(delegate: delegate)
        let root = try XCTUnwrap(modal.topViewController)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        let source = try XCTUnwrap(modal.topViewController)
        var finished: LYOpenResult?
        let opening = Task {
            finished = await router.open(.slowChat("ready"), options: .init(animated: false, from: source))
        }
        await waitUntil { self.gate.waiting == 1 }
        let interaction = UIPercentDrivenInteractiveTransition()
        delegate.interaction = interaction
        modal.popViewController(animated: true)
        await waitUntil { modal.transitionCoordinator?.isInteractive == true }
        interaction.update(0.3)
        interaction.cancel()
        await waitUntil { modal.transitionCoordinator == nil }
        delegate.interaction = nil
        XCTAssertTrue(modal.topViewController === source)
        XCTAssertNil(finished)
        XCTAssertTrue(router.isNavigating)
        gate.open()
        await opening.value
        XCTAssertEqual(finished, .created)
        XCTAssertEqual((modal.topViewController as? TestPage)?.identity, .chat("ready"))
    }

    func testFullscreenCoverDoesNotCleanManagedModalBeforeActualDismissal() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController as? TestPage)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        let source = try XCTUnwrap(modal.topViewController as? TestPage)
        let cover = UIViewController()
        cover.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { continuation in
            modal.present(cover, animated: false) { continuation.resume() }
        }
        await Task.yield()
        XCTAssertEqual(root.removedCount, 0)
        XCTAssertEqual(source.removedCount, 0)
        XCTAssertEqual(router.managedNavigations.count, 1)
        await dismiss(cover)
        await waitUntil { modal.viewIfLoaded?.window != nil && modal.presentedViewController == nil }
        let result = await router.open(.profile("p"), options: .init(animated: false, from: source))
        XCTAssertEqual(result, .created)
        await dismiss(modal)
        await waitUntil { self.router.managedNavigations.isEmpty }
        XCTAssertEqual(root.removedCount, 0, "业务自行关闭不属于路由清理")
        XCTAssertEqual(source.removedCount, 0)
    }

    func testDismissalPreservesBusinessDelegateInstalledAfterAdoption() async throws {
        let original = ModalDelegate()
        let replacement = ModalDelegate()
        let modal = await presentModal(delegate: original)
        let root = try XCTUnwrap(modal.topViewController)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        modal.delegate = replacement
        await dismiss(modal)
        await waitUntil { self.router.managedNavigations.isEmpty }
        XCTAssertTrue(modal.delegate === replacement)
    }

    func testDelayedDismissalObservationReleasesBridgeWithoutCleaningBusinessDismissal() async throws {
        var modal: UINavigationController? = await presentModal()
        let root = try XCTUnwrap(modal?.topViewController as? TestPage)
        _ = await router.open(.club("retained"), options: .init(animated: false, from: root))
        let page = try XCTUnwrap(modal?.topViewController as? TestPage)
        let observationView = try XCTUnwrap(modal?.presentationController?.containerView?.subviews.compactMap { $0 as? PresentationRemovalView }.first)
        let deliverRemoval = try XCTUnwrap(observationView.onRemoved)
        // 控制原本经 Task 延后的通知顺序，确保真正覆盖导航栈先释放的情况。
        observationView.onRemoved = nil
        weak var releasedNavigation: UINavigationController?
        releasedNavigation = modal
        modal?.dismiss(animated: false)
        modal = nil
        await waitUntil { releasedNavigation == nil }
        XCTAssertNil(root.parent)
        XCTAssertNil(page.parent)

        deliverRemoval()
        await waitUntil { self.router.managedNavigations.isEmpty }
        XCTAssertEqual(root.removedCount, 0)
        XCTAssertEqual(page.removedCount, 0)
        deliverRemoval()
        XCTAssertEqual(root.removedCount, 0)
        XCTAssertEqual(page.removedCount, 0)
    }

    func testDelayedDismissalObservationTerminatesReleasedTargetPreparation() async throws {
        var modal: UINavigationController? = await presentModal()
        let source = try XCTUnwrap(modal?.topViewController as? TestPage)
        var finished: LYOpenResult?
        let opening = Task {
            finished = await router.open(.slowChat("released"), options: .init(animated: false, from: source))
        }
        await waitUntil { self.gate.waiting == 1 }
        let observationView = try XCTUnwrap(modal?.presentationController?.containerView?.subviews.compactMap { $0 as? PresentationRemovalView }.first)
        let deliverRemoval = try XCTUnwrap(observationView.onRemoved)
        observationView.onRemoved = nil
        let targetIdentity = try ObjectIdentifier(XCTUnwrap(modal))
        weak var releasedNavigation: UINavigationController?
        releasedNavigation = modal
        modal?.dismiss(animated: false)
        modal = nil
        await waitUntil { releasedNavigation == nil }
        XCTAssertNil(router.currentExecution?.targetNavigation)
        XCTAssertEqual(router.currentExecution?.targetNavigationID, targetIdentity)

        deliverRemoval()
        await waitUntil { finished != nil }
        XCTAssertEqual(finished, .failed(.contextChanged))
        XCTAssertTrue(router.managedNavigations.isEmpty)
        XCTAssertEqual(source.removedCount, 0)
        gate.open()
        await opening.value
        XCTAssertEqual(host.allNavigationControllers[0].viewControllers.count, 1)
    }

    func testDelayedDismissalObservationPreservesReparentedPage() async throws {
        var modal: UINavigationController? = await presentModal()
        let root = try XCTUnwrap(modal?.topViewController as? TestPage)
        _ = await router.open(.club("moved"), options: .init(animated: false, from: root))
        let page = try XCTUnwrap(modal?.topViewController as? TestPage)
        let observationView = try XCTUnwrap(modal?.presentationController?.containerView?.subviews.compactMap { $0 as? PresentationRemovalView }.first)
        let deliverRemoval = try XCTUnwrap(observationView.onRemoved)
        observationView.onRemoved = nil
        weak var releasedNavigation: UINavigationController?
        releasedNavigation = modal
        modal?.dismiss(animated: false)
        modal = nil
        await waitUntil { releasedNavigation == nil }
        let home = host.allNavigationControllers[0]
        home.pushViewController(page, animated: false)

        deliverRemoval()
        XCTAssertTrue(router.managedNavigations.isEmpty)
        XCTAssertEqual(root.removedCount, 0)
        XCTAssertEqual(page.removedCount, 0)
        XCTAssertTrue(home.topViewController === page)
    }

    func testRetainedContextKeepsItsTargetStackAfterExecutionSettles() async throws {
        var homeContext: LYRouteContext<AppRoute>?
        let home = host.allNavigationControllers[0]
        let homeResult = router.performUserNavigation(route: .club("home"), source: .user) { context in
            homeContext = context
            context.markPerformed()
        }
        XCTAssertEqual(homeResult, .performed)
        XCTAssertNil(router.currentExecution)
        XCTAssertTrue(homeContext?.navigationController === home)
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController)
        var modalContext: LYRouteContext<AppRoute>?
        let modalResult = router.performUserNavigation(route: .club("modal"), source: .user,
                                                       options: .init(animated: false, from: root)) { context in
            modalContext = context
            context.markPerformed()
        }
        XCTAssertEqual(modalResult, .performed)
        XCTAssertNil(router.currentExecution)
        XCTAssertTrue(modalContext?.navigationController === modal)
        XCTAssertTrue(homeContext?.navigationController === home)
    }

    func testAnimatedModalDismissalKeepsExecutionUntilCompletion() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController as? TestPage)
        let client = router.makeClient(from: root)
        let closing = Task { await client.dismiss(animated: true) }
        await waitUntil { self.router.currentExecution?.isDismissing == true }
        XCTAssertTrue(router.isNavigating)
        XCTAssertEqual(router.request(.club("during-dismissal")), .ignored)
        let result = await closing.value
        XCTAssertEqual(result, .performed)
        XCTAssertFalse(router.isNavigating)
        XCTAssertEqual(host.allNavigationControllers[0].viewControllers.count, 1)
        await waitUntil { root.removedCount == 1 }
        router.navigationDidStabilize()
        XCTAssertEqual(root.removedCount, 1, "路由器关闭的模态只清理一次")
    }

    func testCoveredModalPreparationDefersThenRunsAfterCoverDismissal() async throws {
        let modal = await presentModal()
        let source = try XCTUnwrap(modal.topViewController)
        let opening = Task {
            await router.open(.slowChat("deferred"), source: .deepLink, options: .init(animated: false, from: source))
        }
        await waitUntil { self.gate.waiting == 1 }
        let cover = UIViewController()
        cover.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { continuation in
            modal.present(cover, animated: false) { continuation.resume() }
        }
        gate.open()
        let result = await opening.value
        XCTAssertEqual(result, .deferred)
        XCTAssertNotNil(router.pending)
        router.navigationDidStabilize()
        XCTAssertNotNil(router.pending, "临时遮挡不能丢弃仍有归属的等待来源")
        await dismiss(cover)
        await waitUntil { self.gate.waiting == 2 }
        gate.open()
        await waitUntil { (modal.topViewController as? TestPage)?.identity == .chat("deferred") }
        XCTAssertEqual(modal.viewControllers.count, 2)
        XCTAssertEqual(host.allNavigationControllers[0].viewControllers.count, 1)
    }

    func testConfirmationReadmitsWithinModalNavigation() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController)
        var confirm: (@MainActor () -> Void)?
        let originalPresenter = router.confirmationPresenter
        router.confirmationPresenter = { alert, navigation, action, presented in
            confirm = action
            return originalPresenter(alert, navigation, action, presented)
        }
        let result = router.performUserNavigation(route: .club("confirmed"), source: .user,
                                                  options: .init(animated: false, from: root)) { context in
            context.confirm(title: "确认", message: nil, confirmTitle: "确定", cancelTitle: "取消") { context in
                context.show { TestPage(.club("confirmed")) }
            }
        }
        XCTAssertEqual(result, .awaitingConfirmation)
        await waitUntil { !self.router.isNavigating }
        XCTAssertTrue(modal.presentedViewController is UIAlertController)
        let action = try XCTUnwrap(confirm)
        action()
        action()
        await waitUntil { modal.viewControllers.count == 2 && modal.presentedViewController == nil }
        XCTAssertEqual((modal.topViewController as? TestPage)?.identity, .club("confirmed"))
        XCTAssertEqual(host.allNavigationControllers[0].viewControllers.count, 1)
    }

    /// 业务自行展示、尚未被接管的模态中，返回与客户端关闭使用同样的准入。
    func testBackWorksInsideUnadoptedModal() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController)
        let pushed = TestPage(.profile("business"))
        modal.pushViewController(pushed, animated: false)
        XCTAssertNil(router.managedNavigations[ObjectIdentifier(modal)])

        await waitUntil { pushed.viewIfLoaded?.window != nil && modal.transitionCoordinator == nil }
        router.navigateBack(from: pushed, in: modal)
        await waitUntil { modal.topViewController === root && !self.router.isNavigating }
        XCTAssertEqual(pushed.removedCount, 1)
    }

    /// `present` 只自动接管普通导航栈；系统导航控制器（相册、邮件等）保留业务代理。
    func testPresentDoesNotAdoptSystemNavigationControllers() async {
        let business = PickerDelegate()
        let picker = UIImagePickerController()
        picker.delegate = business
        picker.modalPresentationStyle = .fullScreen
        _ = router.performUserNavigation(route: .club("picker"), source: .user) { context in
            context.present(picker, animated: false)
        }
        await waitUntil { picker.viewIfLoaded?.window != nil && picker.transitionCoordinator == nil }
        try? await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(picker.delegate === business)
        XCTAssertNil(router.managedNavigations[ObjectIdentifier(picker)])
        await dismiss(picker)

        let flow = UINavigationController(rootViewController: TestPage(nil))
        flow.modalPresentationStyle = .fullScreen
        _ = router.performUserNavigation(route: .club("flow"), source: .user) { context in
            context.present(flow, animated: false)
        }
        await waitUntil { self.router.managedNavigations[ObjectIdentifier(flow)] != nil }
    }

    /// 模态内的登录流程：登录（nil → 会话）后仍由路由器接管该栈，返回与客户端关闭照常生效。
    func testLoginKeepsManagedModalBackAndDismiss() async throws {
        let modal = await presentModal()
        let root = try XCTUnwrap(modal.topViewController as? TestPage)
        _ = await router.open(.club("x"), options: .init(animated: false, from: root))
        let club = try XCTUnwrap(modal.topViewController as? TestPage)
        _ = await router.open(.profile("p"), options: .init(animated: false, from: club))
        let profile = try XCTUnwrap(modal.topViewController as? TestPage)
        let client = router.makeClient(from: club)

        host.sessionID = "signed-in"
        router.sessionDidChange()

        XCTAssertNotNil(router.managedNavigations[ObjectIdentifier(modal)])
        router.navigateBack(from: profile, in: modal)
        await waitUntil { modal.topViewController === club && !self.router.isNavigating && modal.transitionCoordinator == nil }
        let popped = await client.dismiss(animated: false)
        XCTAssertEqual(popped, .reused)
        XCTAssertTrue(modal.topViewController === root)
    }

    private func presentModal(delegate: ModalDelegate? = nil) async -> UINavigationController {
        let navigation = UINavigationController(rootViewController: TestPage(nil, title: "modal root"))
        navigation.modalPresentationStyle = .fullScreen
        navigation.delegate = delegate
        await withCheckedContinuation { continuation in
            host.tabBarController.present(navigation, animated: false) { continuation.resume() }
        }
        await waitUntil { navigation.viewIfLoaded?.window != nil && navigation.transitionCoordinator == nil }
        return navigation
    }

    private func dismiss(_ controller: UIViewController) async {
        await withCheckedContinuation { continuation in
            controller.dismiss(animated: false) { continuation.resume() }
        }
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool, timeout: TimeInterval = 3) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertTrue(condition(), "等待条件超时")
    }
}

@MainActor
private final class PickerDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {}

@MainActor
private final class ModalDelegate: NSObject, UINavigationControllerDelegate {
    let animator = ModalAnimator()
    var interaction: UIPercentDrivenInteractiveTransition?
    private(set) var didShowCount = 0
    private(set) var animationRequests = 0

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        didShowCount += 1
    }

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        animationRequests += 1
        return animator
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        interaction
    }
}

@MainActor
private final class ModalAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.25
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        guard let to = context.view(forKey: .to), let from = context.view(forKey: .from) else {
            context.completeTransition(false)
            return
        }
        context.containerView.insertSubview(to, belowSubview: from)
        UIView.animate(withDuration: transitionDuration(using: context)) {
            from.alpha = 0
        } completion: { _ in
            from.alpha = 1
            context.completeTransition(!context.transitionWasCancelled)
        }
    }
}
