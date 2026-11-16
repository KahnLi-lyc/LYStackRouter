import LYStackRouter
import UIKit
#if ROUTER_DISCOVERY
    import LYStackRouterDiscovery
#endif

/// 不依赖 XCTest 的消费宿主，可在 iOS 16 运行同一组公开接口冒烟。
@main
@MainActor
final class CompatibilityApp: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = CompatibilityScene.self
        return configuration
    }
}

/// 每个窗口分别创建宿主和路由器，页面真实出现后才开始验证。
@MainActor
final class CompatibilityScene: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private var probe: CompatibilityProbe?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let root = CompatibilityPage(identity: nil)
        let host = LYSingleStackHost(root: root)
        host.isReady = false
        let gate = CompatibilityGate()
        var environment = LYRouteEnvironment()
        environment.provide(CompatibilityGate.self, gate)
        do {
            let modules: LYRouteModuleSet<CompatibilityRoute>
            #if ROUTER_DISCOVERY
                modules = .discovered()
            #else
                modules = .explicit([CompatibilityModule.self])
            #endif
            let router = try LYStackRouter<CompatibilityRoute>.build(host: host, modules: modules, environment: environment)
            let probe = CompatibilityProbe(router: router, host: host, root: root, gate: gate)
            self.probe = probe
            root.onFirstAppearance = { [weak probe] in
                Task { @MainActor [weak probe] in await probe?.run() }
            }
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host.navigationController
            self.window = window
            window.makeKeyAndVisible()
        } catch {
            CompatibilityProbe.writeReport(passed: false, checks: ["assembly: \(error)"])
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        probe?.stop()
        probe = nil
        window?.rootViewController = nil
        window = nil
    }
}
