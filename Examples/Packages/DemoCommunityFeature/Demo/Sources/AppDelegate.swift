import DemoRouteContract
import DemoUIKit
import LYStackRouter
import UIKit
import DemoCommunityFeature

/// 独立模块示例仅组装自己的路由模块，跨模块请求使用占位兜底。
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "Module", sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ModuleSceneDelegate.self
        return configuration
    }
}

final class ModuleSceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var host: ModuleHost?
    private var router: LYStackRouter<DemoRoute>?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let metrics = DemoMetrics()
        let root = DemoPage(pageID: "module.root", title: "DemoCommunityFeature", identity: nil, metrics: metrics)
        let host = ModuleHost(root: root)
        var environment = LYRouteEnvironment()
        environment.provide(DemoMetrics.self, metrics)
        do {
            let router = try LYStackRouter<DemoRoute>.build(
                host: host,
                modules: .explicit([CommunityRouteModule.self]),
                environment: environment,
                url: LYURLConfiguration(schemes: ["lydemo"]),
                fallback: .placeholder,
                allowsUnregistered: true
            )
            let client = router.makeClient(from: root)
            root.open = { route in Task { _ = await client.open(route) } }
            root.loadViewIfNeeded()
            root.addButton("打开模块页面", id: "module.open") { [weak root] in root?.open(.club("A")) }
            root.addButton("打开未组装模块", id: "module.fallback") { [weak root] in root?.open(.wallet) }
            root.addButton("模态流程", id: "module.flow") { [weak root] in root?.open(.flow) }
            self.router = router
        } catch {
            fatalError("独立模块组装失败：\(error)")
        }
        self.host = host
        let window = UIWindow(windowScene: scene)
        window.rootViewController = host.navigationController
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        router?.tearDown()
        router = nil
        host = nil
        window = nil
    }
}

/// 独立 Demo 将模块声明的消息域映射到唯一导航栈。
@MainActor
private final class ModuleHost: LYRouterHost, LYNavigationEventSource {
    private let stack: LYSingleStackHost

    init(root: UIViewController) {
        stack = LYSingleStackHost(root: root)
    }

    var navigationController: UINavigationController {
        stack.navigationController
    }

    var routerSessionID: String? {
        nil
    }

    var isRouterReady: Bool {
        true
    }

    var routerRootViewController: UIViewController? {
        navigationController
    }

    var activeNavigationController: UINavigationController? {
        navigationController
    }

    var onNavigationDidShow: ((UINavigationController) -> Void)? {
        get { stack.onNavigationDidShow }
        set { stack.onNavigationDidShow = newValue }
    }

    func navigationDomain(for placement: LYRoutePlacement) -> [UINavigationController] {
        placement == .current || placement == .messages ? [navigationController] : []
    }

    func select(_ placement: LYRoutePlacement) -> UINavigationController? {
        placement == .current || placement == .messages ? navigationController : nil
    }
}
