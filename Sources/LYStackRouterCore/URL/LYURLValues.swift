/// URL 模板匹配出的取值：路径占位符与 query。
public struct LYURLValues: Hashable, Sendable {
    /// 路径占位符的取值，键为模板中的占位名。
    public var path: [String: String]
    /// query 参数。重复键的 URL 在解析阶段已被拒绝。
    public var query: [String: String]

    /// 创建取值。
    public init(path: [String: String] = [:], query: [String: String] = [:]) {
        self.path = path
        self.query = query
    }

    /// 先查路径占位符，再查 query。
    public subscript(key: String) -> String? {
        path[key] ?? query[key]
    }
}
