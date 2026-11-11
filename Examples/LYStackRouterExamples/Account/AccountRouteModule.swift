import DemoRouteContract
import DemoUIKit
import LYStackRouterDiscovery
import UIKit

/// 账号操作，由宿主注入。模块不持有账号状态。
@MainActor
struct DemoAccount {
    let isSignedIn: () -> Bool
    let signIn: () -> Void
}

/// App 自己的模块：登录页与需要登录的钱包动作。与业务模块一样被自动发现。
@LYRouteModule
struct AccountRouteModule: LYRouteModule {
    // MARK: - Properties

    static let moduleID = "account"

    private let metrics: DemoMetrics
    private let account: DemoAccount

    // MARK: - Initialization

    init(environment: LYRouteEnvironment) throws {
        metrics = try environment.require(DemoMetrics.self)
        account = try environment.require(DemoAccount.self)
    }

    // MARK: - Internal

    func register(into builder: inout LYStackRouteRegistry<DemoRoute>.Builder) {
        let metrics = metrics
        let account = account
        builder.page(.login) { _, context in
            context.show { LoginPage(metrics: metrics, account: account, context: context) }
        }
        // 动作路由：不改变导航栈，结果为 `.performed`。未登录时由会话拦截器处理。
        builder.action(.wallet, policy: .init(allowsExternal: true, requiresSession: true)) { _, context in
            let sheet = DemoPage(pageID: "wallet", title: "钱包", identity: nil, metrics: metrics)
            context.present(UINavigationController(rootViewController: sheet))
            context.markPerformed()
        }
    }
}

/// 登录页：登录后回到上一页。
final class LoginPage: DemoPage {
    private let account: DemoAccount
    private let context: LYRouteContext<DemoRoute>

    init(metrics: DemoMetrics, account: DemoAccount, context: LYRouteContext<DemoRoute>) {
        self.account = account
        self.context = context
        super.init(pageID: "login", title: "登录", identity: nil, metrics: metrics)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addNote("钱包需要登录。登录后等待中的外部请求会继续执行。")
        addButton("登录", id: "login.signIn") { [weak self] in
            guard let self else { return }
            account.signIn()
            context.back(from: self)
        }
    }
}
