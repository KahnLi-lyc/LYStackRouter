import DemoMessages
import DemoRoutes
import LYStackRouterDiscovery
import UIKit

/// 示例 App 的场景：每个窗口创建自己的宿主与路由器，不使用单例。
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    // MARK: - Properties

    var window: UIWindow?

    private let metrics = DemoMetrics()
    private var host: DemoHost?
    private var router: LYStackRouter<DemoRoute>?
    private weak var me: MeViewController?

    // MARK: - UIWindowSceneDelegate

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let home = HomeViewController(metrics: metrics)
        let conversations = ConversationsViewController(metrics: metrics)
        // 先放好三个导航栈再创建宿主，宿主初始化时即可成为它们的代理；“我的”页依赖构建结果，稍后填入根页面。
        let meNavigation = UINavigationController()
        meNavigation.tabBarItem = UITabBarItem(title: "我的", image: UIImage(systemName: "person"), selectedImage: nil)
        let tabBar = UITabBarController()
        tabBar.viewControllers = [
            Self.tab(home, title: "首页", image: "house"),
            Self.tab(conversations, title: "消息", image: "bubble.left.and.bubble.right"),
            meNavigation
        ]
        let host = DemoHost(tabs: LYTabBarHost(tabBarController: tabBar, placements: [.home: 0, .messages: 1, .me: 2]))
        let account = DemoAccount(
            isSignedIn: { [weak host] in host?.sessionID != nil },
            signIn: { [weak self] in self?.setSignedIn(true) }
        )
        let router: LYStackRouter<DemoRoute>
        do {
            router = try DemoAssembly.makeRouter(host: host, metrics: metrics, account: account)
        } catch {
            // 漏注册、URL 冲突或缺依赖在启动时暴露，而不是在用户点击时悄悄失效。
            fatalError("路由表无效：\(error)")
        }
        let assembly = "组装：\(DemoAssembly.mode.rawValue) · 模块：\(router.moduleIDs.joined(separator: ","))"
        // 输出组装结果，便于在 Release 构建中确认自动发现没有被链接器裁掉。
        print("LYStackRouterExamples \(assembly)")
        let me = MeViewController(metrics: metrics, assembly: assembly)
        meNavigation.setViewControllers([me], animated: false)
        let open: (DemoRoute) -> Void = { [weak router] route in _ = router?.request(route) }
        home.open = open
        conversations.open = open
        me.open = open
        home.openURL = { [weak self] url in self?.openDeepLink(url) }
        me.signOut = { [weak self] in self?.setSignedIn(false) }
        me.setDegraded = { [weak router] degraded in
            router?.rewrite = degraded ? LYRouteRewrite(disabledKinds: ["member"]) : .none
        }
        me.presentSheetThenDeepLink = { [weak self, weak me] in
            guard let me, let metrics = self?.metrics else { return }
            me.present(UINavigationController(rootViewController: SheetPage(metrics: metrics)), animated: true)
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if let url = URL(string: "lydemo://club/99") { self?.openDeepLink(url) }
            }
        }
        me.deliverDeepLinkLater = { [weak self] in
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if let url = URL(string: "lydemo://club/77") { self?.openDeepLink(url) }
            }
        }
        self.host = host
        self.router = router
        self.me = me

        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = tabBar
        window.makeKeyAndVisible()
        self.window = window
        // 根视图上屏后才允许导航；冷启动携带的深链此前进入等待。
        host.isReady = true
        router.navigationDidStabilize()
        if let url = connectionOptions.urlContexts.first?.url { openDeepLink(url) }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        if let url = URLContexts.first?.url { openDeepLink(url) }
    }

    // MARK: - Private

    private func openDeepLink(_ url: URL) {
        Task { @MainActor [weak router] in _ = await router?.openURL(url, source: .deepLink) }
    }

    private func setSignedIn(_ signedIn: Bool) {
        host?.sessionID = signedIn ? "demo-user" : nil
        router?.sessionDidChange()
        me?.showSession(signedIn)
    }

    private static func tab(_ root: UIViewController, title: String, image: String) -> UINavigationController {
        let navigation = UINavigationController(rootViewController: root)
        navigation.tabBarItem = UITabBarItem(title: title, image: UIImage(systemName: image), selectedImage: nil)
        return navigation
    }
}
