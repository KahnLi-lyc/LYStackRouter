import DemoRouteContract
import DemoUIKit
import LYStackRouterDiscovery
import UIKit

/// 示例业务自己的账号状态；路由库不读取它，也不决定登录后的继续策略。
@MainActor
final class DemoAccount {
    var isSignedIn = false
    var didSignIn: () -> Void = {}
    var navigationDidStabilize: () -> Void = {}

    func signIn() {
        isSignedIn = true
        didSignIn()
    }
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
        // 业务处理器自行决定登录跳转；外部请求受阻后等待业务显式通知稳定。
        builder.action(.wallet, policy: .init(allowsExternal: true)) { _, context in
            guard account.isSignedIn else {
                if context.source.isExternal { context.fail(.blocked) }
                else { context.continueNavigation(to: .login) }
                return
            }
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
            // 普通登录保留上下文；返回引起的转场结束后，等待中的钱包请求可继续。
            account.navigationDidStabilize()
        }
    }
}
