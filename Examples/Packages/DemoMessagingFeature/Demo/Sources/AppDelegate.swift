import DemoRouteContract
import DemoUIKit
import LYStackRouter
import UIKit
import DemoMessagingFeature

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
    private var demo: ModuleDemo?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        do {
            let demo = try ModuleDemo(
                scene: scene,
                title: "DemoMessagingFeature",
                modules: .explicit([MessagesRouteModule.self]),
                entries: [
                    .init(title: "打开模块页面", id: "module.open", route: .chat("c1")),
                    .init(title: "打开未组装模块", id: "module.fallback", route: .wallet)
                ]
            )
            self.demo = demo
            window = demo.window
        } catch {
            fatalError("独立模块组装失败：\(error)")
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        demo?.tearDown()
        demo = nil
        window = nil
    }
}
