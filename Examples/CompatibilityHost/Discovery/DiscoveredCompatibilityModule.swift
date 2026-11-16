import LYStackRouterDiscovery

/// Release 消费工程必须在链接后实际发现本模块，不能通过显式补入掩盖发现失败。
@LYRouteModule
struct DiscoveredCompatibilityModule: LYRouteModule {
    static let moduleID = "compatibility"
    private let module: CompatibilityModule

    init(environment: LYRouteEnvironment) throws {
        module = try CompatibilityModule(environment: environment)
    }

    func register(into builder: inout LYStackRouteRegistry<CompatibilityRoute>.Builder) {
        module.register(into: &builder)
    }
}
