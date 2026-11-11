import Foundation

/// 全部模块登记结果的不可变汇总：每个路由种类的策略与处理器，以及 URL 模板表。
///
/// `Context` 是处理器执行时拿到的上下文，由执行引擎决定（UIKit 引擎中为 `LYRouteContext<Route>`）。
/// 注册表只保存无状态的策略与闭包，不保存页面、宿主或请求。
@MainActor
public struct LYRouteRegistry<Route: LYRoutable, Context> {
    // MARK: - Properties

    /// 单个路由种类的登记。
    package struct Entry {
        package let policy: LYRoutePolicy<Route>
        package let handlerKind: LYRouteHandlerKind
        package let moduleID: String
        package let location: String
        package let handle: @MainActor (Route, Context) -> Void
    }

    package let entries: [Route.Kind: Entry]
    package let urlTable: LYURLTable<Route>

    // MARK: - Public

    /// 已登记的路由种类。
    public var registeredKinds: Set<Route.Kind> {
        Set(entries.keys)
    }

    /// 读取某个路由种类的策略；未登记时返回 nil。
    public func policy(for kind: Route.Kind) -> LYRoutePolicy<Route>? {
        entries[kind]?.policy
    }

    /// 把 URL 解析为路由，先应用重写规则；不属于本 App 或无法匹配时返回 nil。
    public func route(
        for url: URL,
        configuration: LYURLConfiguration,
        rewrite: LYRouteRewrite = .none
    ) -> Route? {
        guard let components = configuration.components(of: url) else { return nil }
        let segments = LYRouteRewrite.apply(rewrite.compiled().rules, to: components.segments)
        return urlTable.route(segments: segments, query: components.query)
    }

    /// 为路由生成 URL；`universalLinkHost` 为 nil 时使用自定义 scheme。
    ///
    /// 生成的 URL 必须能被整张路由表解析回同一路由：首选模板被更具体的模板截获（例如 `club/new`）时换用下一个能表达它的模板，
    /// 都不行时返回 nil。`parse` 会规范化参数的路由，如果规范化后不等于原路由，同样返回 nil。往返校验不应用远程重写。
    public func url(
        for route: Route,
        configuration: LYURLConfiguration,
        universalLinkHost: String? = nil
    ) -> URL? {
        for candidate in urlTable.componentsCandidates(for: route) {
            guard let generated = configuration.url(
                segments: candidate.segments,
                query: candidate.query,
                universalLinkHost: universalLinkHost
            ), self.route(for: generated, configuration: configuration) == route else { continue }
            return generated
        }
        return nil
    }
}
