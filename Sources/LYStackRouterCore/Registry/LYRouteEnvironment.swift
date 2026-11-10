/// 每个路由器实例各自的依赖容器。
///
/// 宿主在构建路由器前用 `provide` 放入依赖，模块在初始化时用 `require` 取出。
/// 它只在构建期间使用，不是全局服务定位器；不同窗口的路由器各自持有自己的环境。
@MainActor
public struct LYRouteEnvironment {
    // MARK: - Properties

    private var values: [ObjectIdentifier: Any] = [:]

    // MARK: - Initialization

    /// 创建空环境。
    public init() {}

    // MARK: - Public

    /// 放入一个依赖；同类型重复放入时以最后一次为准。
    public mutating func provide<Value>(_ type: Value.Type, _ value: Value) {
        values[ObjectIdentifier(type)] = value
    }

    /// 读取一个依赖；不存在时返回 nil。
    public func value<Value>(_ type: Value.Type) -> Value? {
        values[ObjectIdentifier(type)] as? Value
    }

    /// 读取一个必需依赖；不存在时抛出错误，由 `build()` 补上模块名后报告。
    public func require<Value>(_ type: Value.Type) throws -> Value {
        guard let value = value(type) else { throw MissingDependency(type: String(describing: type)) }
        return value
    }

    // MARK: - Internal

    /// `require` 抛出的内部错误，构建时转换为 `LYRouteBuildError.missingDependency`。
    package struct MissingDependency: Error {
        package let type: String
    }
}
