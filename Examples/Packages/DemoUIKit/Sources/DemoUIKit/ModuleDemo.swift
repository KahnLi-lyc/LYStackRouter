import DemoRouteContract
import LYStackRouter
import UIKit

/// 独立模块 Demo 的公共组装：单栈宿主、只列出本模块、占位兜底并允许未注册路由。
///
/// 两个功能包的 Demo 只提供模块列表与入口按钮，其余组装方式保持一致。
@MainActor
public final class ModuleDemo {
    // MARK: - Properties

    /// 根页面上的入口按钮。
    public struct Entry {
        let title: String
        let id: String
        let route: DemoRoute

        /// 创建入口：`id` 作为无障碍标识供 UI 测试使用。
        public init(title: String, id: String, route: DemoRoute) {
            self.title = title
            self.id = id
            self.route = route
        }
    }

    /// Demo 的主窗口，由场景代理持有。
    public let window: UIWindow
    private let host: ModuleDemoHost
    private let router: LYStackRouter<DemoRoute>

    // MARK: - Initialization

    /// 组装模块并显示根页面；漏注册、URL 冲突或缺依赖在这里抛出。
    public init(scene: UIWindowScene, title: String, modules: LYRouteModuleSet<DemoRoute>, entries: [Entry]) throws {
        let metrics = DemoMetrics()
        let root = DemoPage(pageID: "module.root", title: title, identity: nil, metrics: metrics)
        host = ModuleDemoHost(root: root)
        var environment = LYRouteEnvironment()
        environment.provide(DemoMetrics.self, metrics)
        router = try LYStackRouter<DemoRoute>.build(
            host: host,
            modules: modules,
            environment: environment,
            url: LYURLConfiguration(schemes: ["lydemo"]),
            fallback: .placeholder,
            allowsUnregistered: true
        )
        let client = router.makeClient(from: root)
        root.open = { route in Task { _ = await client.open(route) } }
        root.loadViewIfNeeded()
        for entry in entries {
            root.addButton(entry.title, id: entry.id) { [weak root] in root?.open(entry.route) }
        }
        window = UIWindow(windowScene: scene)
        window.rootViewController = host.navigationController
        window.makeKeyAndVisible()
    }

    // MARK: - Teardown

    /// 场景断开时停止路由器并隐藏窗口；重复调用安全。
    public func tearDown() {
        router.tearDown()
        window.isHidden = true
    }
}

/// 独立 Demo 将模块声明的消息域映射到唯一导航栈。
@MainActor
private final class ModuleDemoHost: LYRouterHost, LYNavigationEventSource {
    // MARK: - Properties

    private let stack: LYSingleStackHost

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

    // MARK: - Initialization

    init(root: UIViewController) {
        stack = LYSingleStackHost(root: root)
    }

    // MARK: - LYRouterHost

    func navigationDomain(for placement: LYRoutePlacement) -> [UINavigationController] {
        placement == .current || placement == .messages ? [navigationController] : []
    }

    func select(_ placement: LYRoutePlacement) -> UINavigationController? {
        placement == .current || placement == .messages ? navigationController : nil
    }
}
