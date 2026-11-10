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

    /// 为路由生成 URL；`universalLinkHost` 为 nil 时使用自定义 scheme。没有模板能表达该路由时返回 nil。
    public func url(
        for route: Route,
        configuration: LYURLConfiguration,
        universalLinkHost: String? = nil
    ) -> URL? {
        guard let components = urlTable.components(for: route) else { return nil }
        return configuration.url(
            segments: components.segments,
            query: components.query,
            universalLinkHost: universalLinkHost
        )
    }
}
