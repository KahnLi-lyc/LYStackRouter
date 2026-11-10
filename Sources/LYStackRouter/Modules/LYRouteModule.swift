#if canImport(UIKit)
    /// 引擎使用的注册表类型：处理器拿到 `LYRouteContext`。
    public typealias LYStackRouteRegistry<Route: LYRoutable> = LYRouteRegistry<Route, LYRouteContext<Route>>

    /// 业务模块：在自己的包里登记自己负责的页面、动作与 URL。
    ///
    /// 模块通过 `init(environment:)` 取得依赖，然后在 `register(into:)` 中登记。
    /// 路由器构建时逐个创建模块并收集登记，最后做穷尽、重复与冲突检查。
    @MainActor
    public protocol LYRouteModule<Route> {
        /// 模块负责的路由类型。
        associatedtype Route: LYRoutable

        /// 稳定的模块标识，用于诊断、排序与去重。
        static var moduleID: String { get }

        /// 从环境中取出依赖；缺少依赖时抛出，构建会报告模块名与类型。
        init(environment: LYRouteEnvironment) throws

        /// 登记页面、动作与 URL 模板。
        func register(into builder: inout LYStackRouteRegistry<Route>.Builder)
    }

    /// 参与构建的模块集合。
    @MainActor
    public struct LYRouteModuleSet<Route: LYRoutable> {
        // MARK: - Properties

        package let resolve: @MainActor () -> [any LYRouteModule<Route>.Type]

        // MARK: - Initialization

        /// 由解析闭包创建；可选的自动发现模块通过它扩展。
        package init(resolve: @escaping @MainActor () -> [any LYRouteModule<Route>.Type]) {
            self.resolve = resolve
        }

        // MARK: - Public

        /// 显式列出模块，按给定顺序登记。单元测试、模块 Demo 与不使用宏的 App 推荐使用。
        public static func explicit(_ modules: [any LYRouteModule<Route>.Type]) -> LYRouteModuleSet {
            LYRouteModuleSet { modules }
        }
    }
#endif
