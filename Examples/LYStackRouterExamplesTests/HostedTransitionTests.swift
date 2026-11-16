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
        let rootPage = try XCTUnwrap(home.topViewController as? TestPage)
        // 容器挂入窗口不代表其页面已完成首次上屏；此时协调器也可能为空。
        // 等待真实 viewDidAppear，再验证动画语义，避免把 UIKit 排队中的初始展示当成稳定栈。
        await waitUntil {
            UIApplication.shared.applicationState == .active
                && self.window.isKeyWindow && !self.window.isHidden
                && rootPage.viewIfLoaded?.window === self.window
                && rootPage.appearanceEvents.last == "didAppear" && self.isIdle
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

    func testSingleStackHostForwardsCustomAnimationAndInteractionDelegate() async throws {
        let business = HostedAnimationDelegate()
        let root = TestPage(nil, title: "single-root")
        let singleHost = LYSingleStackHost(root: root)
        singleHost.forwardingDelegate = business
        let delegate = try XCTUnwrap(singleHost.navigationController.delegate)
        let animationSelector = #selector(UINavigationControllerDelegate.navigationController(_:animationControllerFor:from:to:))
        let interactionSelector = #selector(UINavigationControllerDelegate.navigationController(_:interactionControllerFor:))
        XCTAssertTrue(delegate.responds(to: animationSelector), "业务动画能力应对 UIKit 可见")
        XCTAssertTrue(delegate.responds(to: interactionSelector), "业务交互能力应对 UIKit 可见")
        let animation = delegate.navigationController?(
            singleHost.navigationController, animationControllerFor: .push,
            from: UIViewController(), to: UIViewController()
        )
        XCTAssertTrue(animation === business.animator)
        let interaction = delegate.navigationController?(singleHost.navigationController, interactionControllerFor: business.animator)
        XCTAssertTrue(interaction === business.interaction)
        XCTAssertEqual(business.animationRequests, 1)
        XCTAssertEqual(business.interactionRequests, 1)
        singleHost.forwardingDelegate = nil
        XCTAssertNil(delegate.navigationController?(
            singleHost.navigationController, animationControllerFor: .push,
            from: UIViewController(), to: UIViewController()
        ), "没有业务动画时返回 nil，保留 UIKit 默认转场")
        singleHost.forwardingDelegate = business
        window.rootViewController = singleHost.navigationController
        await waitUntil { root.appearanceEvents.last == "didAppear" }
        business.suppliesInteraction = false
        let pushed = TestPage(nil, title: "animated")
        singleHost.navigationController.pushViewController(pushed, animated: true)
        await waitUntil { pushed.appearanceEvents.last == "didAppear" && singleHost.navigationController.transitionCoordinator == nil }
        XCTAssertEqual(business.animationRequests, 2, "真实 UIKit push 必须查询业务动画，不能仅手动调用代理方法")
        XCTAssertTrue(singleHost.navigationController.topViewController === pushed)
        await verifyChangingAnimationDelegates(in: singleHost.navigationController) { singleHost.forwardingDelegate = $0 }
    }

    func testAnimatedReuseCleansRemovedPagesOnlyAfterTransition() async throws {
        recordTransitionState("before-first-open")
        let created = await router.open(.club("x"))
        recordTransitionState("after-first-open", result: created)
        XCTAssertEqual(created, .created)
        let profile = await router.open(.profile("a"))
        recordTransitionState("after-profile-open", result: profile)
        XCTAssertEqual(profile, .created)
        let middle = try XCTUnwrap(home.topViewController as? TestPage)
        let second = await router.open(.club("y"))
        recordTransitionState("after-second-open", result: second)
        XCTAssertEqual(second, .created)
        let top = try XCTUnwrap(home.topViewController as? TestPage)

        let reused = router.request(.club("x"))
        recordTransitionState("after-reuse-request", result: reused)
        XCTAssertEqual(reused, .reused)
        XCTAssertNotNil(home.transitionCoordinator, "窗口中的回退带转场")
        XCTAssertEqual(middle.removedCount + top.removedCount, 0, "转场结束前不清理")
        let settled = await router.waitForNavigation()
        recordTransitionState("after-reuse-wait", result: settled)
        XCTAssertEqual(settled, .reused)
        XCTAssertEqual(middle.removedCount, 1)
        XCTAssertEqual(top.removedCount, 1)
        XCTAssertEqual(home.viewControllers.count, 2)
    }

    func testTabHostUpdatesUIKitAnimationCapabilitiesWhenForwardingDelegateChanges() async {
        let business = HostedAnimationDelegate()
        business.suppliesInteraction = false
        host.forwardingDelegate = business
        let pushed = TestPage(nil, title: "tab-animated")
        home.pushViewController(pushed, animated: true)
        await waitUntil { pushed.appearanceEvents.last == "didAppear" && self.isIdle }
        XCTAssertEqual(business.animationRequests, 1, "设置转发代理后，真实 UIKit 必须更新缓存的动画能力")
        XCTAssertTrue(home.topViewController === pushed)
        await verifyChangingAnimationDelegates(in: home) { self.host.forwardingDelegate = $0 }
    }

    func testSingleStackHostUsesLateInjectedCustomInteractivePush() async {
        let root = TestPage(nil)
        let singleHost = LYSingleStackHost(root: root)
        window.rootViewController = singleHost.navigationController
        await waitUntil { root.appearanceEvents.last == "didAppear" }
        let business = HostedAnimationDelegate()
        singleHost.forwardingDelegate = business
        await verifyCustomInteractivePush(in: singleHost.navigationController, delegate: business)
    }

    func testTabHostUsesLateInjectedCustomInteractivePush() async {
        let business = HostedAnimationDelegate()
        host.forwardingDelegate = business
        await verifyCustomInteractivePush(in: home, delegate: business)
    }

    func testSharedWeakDelegateNotifiesEverySubscriberOnce() async throws {
        var business: HostedAnimationDelegate? = HostedAnimationDelegate()
        let released = try WeakReference(XCTUnwrap(business))
        var notifications: [String] = []
        let first = try NavigationDelegateLifetime(delegate: XCTUnwrap(business)) { notifications.append("first") }
        let second = try NavigationDelegateLifetime(delegate: XCTUnwrap(business)) { notifications.append("second") }
        business = nil
        XCTAssertNil(released.value)
        await waitUntil { notifications.count == 2 }
        XCTAssertEqual(Set(notifications), ["first", "second"])
        withExtendedLifetime((first, second)) {}
    }

    func testStoppedWeakDelegateSubscriptionCannotNotifyReplacement() async throws {
        var old: HostedAnimationDelegate? = HostedAnimationDelegate()
        var current: HostedAnimationDelegate? = HostedAnimationDelegate()
        var oldNotifications = 0
        var currentNotifications = 0
        let first = try NavigationDelegateLifetime(delegate: XCTUnwrap(old)) { oldNotifications += 1 }
        first.stop()
        let second = try NavigationDelegateLifetime(delegate: XCTUnwrap(current)) { currentNotifications += 1 }
        old = nil
        current = nil
        await waitUntil { currentNotifications == 1 }
        XCTAssertEqual(oldNotifications, 0)
        withExtendedLifetime((first, second)) {}
    }

    func testQueuedWeakDelegateNotificationCannotNotifyStoppedSubscription() async throws {
        var old: HostedAnimationDelegate? = HostedAnimationDelegate()
        var current: HostedAnimationDelegate? = HostedAnimationDelegate()
        var oldNotifications = 0
        var currentNotifications = 0
        let first = try NavigationDelegateLifetime(delegate: XCTUnwrap(old)) { oldNotifications += 1 }
        old = nil // 同步析构关联对象，先投递 MainActor 通知，再取消订阅；此处不能 await。
        first.stop()
        let second = try NavigationDelegateLifetime(delegate: XCTUnwrap(current)) { currentNotifications += 1 }
        current = nil
        await waitUntil { currentNotifications == 1 }
        XCTAssertEqual(oldNotifications, 0)
        withExtendedLifetime((first, second)) {}
    }

    func testUserTapDuringAnimatedPushIsIgnored() async {
        XCTAssertEqual(router.request(.club("x")), .created)
        XCTAssertTrue(router.isNavigating, "动画 push 期间执行仍在进行")
        XCTAssertEqual(router.request(.club("y")), .ignored)
        await router.waitForNavigation()
        XCTAssertEqual(home.viewControllers.count, 2)
    }

    func testRoutersKeepWindowOwnershipWhenAnotherWindowBecomesKey() async throws {
        let ownRoot = try XCTUnwrap(home.topViewController)
        let otherRoot = TestPage(nil, title: "other-window")
        let otherHost = LYSingleStackHost(root: otherRoot)
        let otherRouter = try LYStackRouter<AppRoute>.build(
            host: otherHost, modules: .explicit([CommunityModule.self]),
            environment: makeEnvironment(), allowsUnregistered: true
        )
        let otherWindow = try UIWindow(windowScene: XCTUnwrap(window.windowScene))
        otherWindow.rootViewController = otherHost.navigationController
        otherWindow.makeKeyAndVisible()
        defer {
            otherRouter.tearDown()
            otherWindow.isHidden = true
            otherWindow.rootViewController = nil
            window.makeKeyAndVisible()
        }
        await waitUntil { otherRoot.appearanceEvents.last == "didAppear" && otherWindow.isKeyWindow }
        let foreign = await router.makeClient(from: otherRoot).open(.club("foreign"), options: .init(animated: false))
        XCTAssertEqual(foreign, .ignored)
        let own = await router.makeClient(from: ownRoot).open(.club("own"), options: .init(animated: false))
        let other = await otherRouter.makeClient(from: otherRoot).open(.club("other"), options: .init(animated: false))
        XCTAssertEqual(own, .created)
        XCTAssertEqual(other, .created)
        XCTAssertEqual((home.topViewController as? TestPage)?.identity, .club("own"))
        XCTAssertEqual((otherHost.navigationController.topViewController as? TestPage)?.identity, .club("other"))
        XCTAssertEqual(home.viewControllers.count, 2)
        XCTAssertEqual(otherHost.navigationController.viewControllers.count, 2)
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

    /// 先建宿主、后放导航栈（示例 App 曾经的顺序）：准备期间用户点系统返回，不经过路由器。
    /// 宿主必须收到 UIKit 的 didShow，才能在准备结束前以 `.contextChanged` 结算原请求。
    func testSystemBackDuringPreparationPreemptsWhenTabsAreAddedAfterHost() async {
        let tabs = UITabBarController()
        let lateHost = LYTabBarHost(
            tabBarController: tabs,
            placements: [LYRoutePlacement("home"): 0, LYRoutePlacement("messages"): 1, LYRoutePlacement("me"): 2]
        )
        tabs.viewControllers = (0 ..< 3).map { _ in UINavigationController(rootViewController: TestPage(nil)) }
        router.attach(lateHost)
        host = lateHost
        window.rootViewController = tabs
        await waitUntil { tabs.viewIfLoaded?.window != nil && self.isIdle }

        _ = await router.open(.club("x"))
        let opening = Task { await router.open(.slowChat("s1")) }
        await waitUntil { self.gate.waiting == 1 }
        home.popViewController(animated: true)
        await waitUntil { !self.router.isNavigating }
        XCTAssertFalse(router.isNavigating, "系统返回后，准备结束前就应释放执行权")
        gate.open()
        let result = await opening.value
        XCTAssertEqual(result, .failed(.contextChanged))
        await waitUntil { self.isIdle }
        XCTAssertEqual(home.viewControllers.count, 1, "迟到的准备不能再展示页面")
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

    private func verifyCustomInteractivePush(in navigation: UINavigationController, delegate: HostedAnimationDelegate) async {
        let page = TestPage(nil)
        navigation.pushViewController(page, animated: true)
        await waitUntil { navigation.transitionCoordinator?.isInteractive == true }
        XCTAssertEqual(delegate.animationRequests, 1)
        XCTAssertEqual(delegate.interactionRequests, 1, "真实 UIKit 必须查询迟注入的业务交互驱动")
        if navigation.transitionCoordinator?.isInteractive == true {
            delegate.interaction.update(0.3)
            delegate.interaction.finish()
        }
        await waitUntil { page.appearanceEvents.last == "didAppear" && navigation.transitionCoordinator == nil }
        XCTAssertTrue(navigation.topViewController === page)
    }

    /// 使用真实 push 验证代理替换、显式清空、弱引用清零及导航代理被业务接管后的归属。
    private func verifyChangingAnimationDelegates(
        in navigation: UINavigationController,
        setDelegate: ((any UINavigationControllerDelegate)?) -> Void
    ) async {
        let first = HostedAnimationDelegate()
        first.suppliesInteraction = false
        let second = HostedAnimationDelegate()
        second.suppliesInteraction = false
        setDelegate(first)
        await pushTestPage(in: navigation)
        XCTAssertEqual(first.animationRequests, 1)
        setDelegate(second)
        await pushTestPage(in: navigation)
        XCTAssertEqual(first.animationRequests, 1)
        XCTAssertEqual(second.animationRequests, 1)
        setDelegate(nil)
        await pushTestPage(in: navigation)
        XCTAssertEqual(second.animationRequests, 1)
        var transient: HostedAnimationDelegate? = HostedAnimationDelegate()
        transient?.suppliesInteraction = false
        let released = WeakReference(transient)
        setDelegate(transient)
        await pushTestPage(in: navigation)
        XCTAssertEqual(transient?.animationRequests, 1)
        transient = nil
        XCTAssertNil(released.value, "宿主不能强持有业务代理")
        let animationSelector = #selector(UINavigationControllerDelegate.navigationController(_:animationControllerFor:from:to:))
        let interactionSelector = #selector(UINavigationControllerDelegate.navigationController(_:interactionControllerFor:))
        await waitUntil {
            navigation.delegate?.responds(to: animationSelector) == false
                && navigation.delegate?.responds(to: interactionSelector) == false
        }
        await pushTestPage(in: navigation)
        navigation.delegate = first
        setDelegate(second)
        XCTAssertTrue(navigation.delegate === first, "业务接管 delegate 后，转发代理变化不能夺回归属")
    }

    private func pushTestPage(in navigation: UINavigationController) async {
        let page = TestPage(nil)
        navigation.pushViewController(page, animated: true)
        await waitUntil { page.appearanceEvents.last == "didAppear" && navigation.transitionCoordinator == nil }
        XCTAssertTrue(navigation.topViewController === page)
    }

    /// 相同诊断用于历史版和当前版，只记录测试身份，不记录业务参数。
    private func recordTransitionState(_ stage: String, result: LYOpenResult? = nil) {
        let execution = router.currentExecution
        let pages = home.viewControllers.map { page in
            let testPage = page as? TestPage
            return "\(page.title ?? "untitled"){appearance:\(testPage?.appearanceEvents ?? []),window:\(page.viewIfLoaded?.window === window),parent:\(page.parent === home),removed:\(testPage?.removedCount ?? -1)}"
        }
        let message = "LYSR_TRANSITION \(stage) active=\(UIApplication.shared.applicationState == .active) scene=\(String(describing: window.windowScene?.activationState)) hidden=\(window.isHidden) key=\(window.isKeyWindow) rootWindow=\(host.tabBarController.viewIfLoaded?.window === window) navigationWindow=\(home.viewIfLoaded?.window === window) stack=\(pages) coordinator=\(String(describing: home.transitionCoordinator)) rootCoordinator=\(String(describing: host.tabBarController.transitionCoordinator)) phase=\(String(describing: execution?.phase)) proposed=\(String(describing: execution?.proposedResult)) executionResult=\(String(describing: execution?.result)) result=\(String(describing: result))"
        print(message)
        let attachment = XCTAttachment(string: message)
        attachment.lifetime = .keepAlways
        add(attachment)
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
private final class HostedAnimationDelegate: NSObject, UINavigationControllerDelegate {
    let animator = HostedAnimator()
    let interaction = UIPercentDrivenInteractiveTransition()
    private(set) var animationRequests = 0
    private(set) var interactionRequests = 0
    var suppliesInteraction = true

    func navigationController(_ navigationController: UINavigationController, animationControllerFor operation: UINavigationController.Operation,
                              from fromVC: UIViewController, to toVC: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
        animationRequests += 1
        return animator
    }

    func navigationController(_ navigationController: UINavigationController,
                              interactionControllerFor animationController: any UIViewControllerAnimatedTransitioning) -> (any UIViewControllerInteractiveTransitioning)? {
        interactionRequests += 1
        return suppliesInteraction ? interaction : nil
    }
}

@MainActor
private final class HostedAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.25
    }

    func animateTransition(using transitionContext: any UIViewControllerContextTransitioning) {
        guard let target = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(false)
            return
        }
        transitionContext.containerView.addSubview(target)
        target.alpha = 0
        UIView.animate(withDuration: transitionDuration(using: transitionContext)) {
            target.alpha = 1
        } completion: { _ in
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
        }
    }
}
