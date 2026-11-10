import DemoCommunity
import DemoMessages
import DemoRoutes
import LYStackRouterDiscovery
import UIKit

/// 组装路由器。启动参数 `-assembly explicit` 使用显式模块列表，默认使用自动发现。
@MainActor
enum DemoAssembly {
    enum Mode: String {
        case discovered
        case explicit
    }

    static var mode: Mode {
        UserDefaults.standard.string(forKey: "assembly").flatMap(Mode.init(rawValue:)) ?? .discovered
    }

    static var modules: LYRouteModuleSet<DemoRoute> {
        switch mode {
        case .discovered:
            .discovered
        case .explicit:
            .explicit([AccountRouteModule.self, CommunityRouteModule.self, MessagesRouteModule.self])
        }
    }

    static func makeRouter(
        host: DemoHost,
        metrics: DemoMetrics,
        account: DemoAccount
    ) throws -> LYStackRouter<DemoRoute> {
        var environment = LYRouteEnvironment()
        environment.provide(DemoMetrics.self, metrics)
        environment.provide(DemoAccount.self, account)
        // 未登录时：用户点击跳到登录页；推送等外部请求进入等待，登录后继续。
        let session = LYRouteInterceptor<DemoRoute>(name: "session", priority: 1000) { request in
            guard request.requiresSession, !account.isSignedIn() else { return .proceed }
            return request.source.isExternal ? .deferUntilReady : .redirect(.login)
        }
        return try LYStackRouter<DemoRoute>.build(
            host: host,
            modules: modules,
            environment: environment,
            interceptors: [session],
            observers: [DemoObserver(metrics: metrics)],
            url: LYURLConfiguration(schemes: ["lydemo"], universalLinkHosts: ["demo.example.com"]),
            fallback: .placeholder
        )
    }
}

/// 把每次结算写进观测数据，界面状态行与 UI 测试读取它。只记录种类与结果。
final class DemoObserver: LYRouteObserver {
    typealias Route = DemoRoute

    private let metrics: DemoMetrics

    init(metrics: DemoMetrics) {
        self.metrics = metrics
    }

    func routeDidSettle(_ kind: DemoRoute.Kind?, source: LYRouteSource, result: LYOpenResult) {
        let name = kind.map { "\($0)" } ?? "url"
        let outcome = switch result {
        case let .failed(failure): "failed.\(failure)"
        default: "\(result)"
        }
        metrics.record("\(name): \(outcome)")
    }
}
