/// 可远程下发的路由重写与降级配置。
///
/// 配置是一份完整快照：下发新配置即替换旧配置，从配置中删掉某一项就等于恢复。
/// - `disabledKinds`：按路由种类名称（`String(describing: kind)`）禁用，请求以 `.unavailable` 失败并走兜底。
/// - `replacements`：URL 路径模板替换，`from` 与 `to` 使用相同的占位名。只做精确模板匹配，不做前缀或正则匹配。
public struct LYRouteRewrite: Hashable, Sendable, Codable {
    // MARK: - Properties

    /// 一条 URL 路径替换规则。
    public struct Replacement: Hashable, Sendable, Codable {
        /// 原路径模板，例如 `club/<id>`。
        public var from: String
        /// 新路径模板，例如 `community/<id>`。
        public var to: String

        /// 创建替换规则。
        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// 被禁用的路由种类名称。
    public var disabledKinds: Set<String>
    /// URL 路径替换规则，按顺序取第一条匹配的。
    public var replacements: [Replacement]

    // MARK: - Initialization

    /// 创建配置。
    public init(disabledKinds: Set<String> = [], replacements: [Replacement] = []) {
        self.disabledKinds = disabledKinds
        self.replacements = replacements
    }

    /// 空配置。
    public static let none = LYRouteRewrite()

    // MARK: - Internal

    /// 该路由种类是否被禁用。
    package func isDisabled(_ kind: some Any) -> Bool {
        disabledKinds.contains(String(describing: kind))
    }

    /// 编译替换规则；写法无效或占位名不一致的规则被跳过，并在 `invalid` 中列出。
    package func compiled() -> (rules: [(from: LYURLTemplate, to: LYURLTemplate)], invalid: [Replacement]) {
        var rules: [(LYURLTemplate, LYURLTemplate)] = []
        var invalid: [Replacement] = []
        for replacement in replacements {
            guard let from = try? LYURLTemplate(replacement.from), let to = try? LYURLTemplate(replacement.to),
                  Self.placeholderNames(from) == Self.placeholderNames(to) else {
                invalid.append(replacement)
                continue
            }
            rules.append((from, to))
        }
        return (rules, invalid)
    }

    /// 应用第一条匹配的替换规则；没有匹配时原样返回。
    package static func apply(
        _ rules: [(from: LYURLTemplate, to: LYURLTemplate)],
        to segments: [String]
    ) -> [String] {
        for rule in rules {
            if let values = rule.from.match(segments), let rewritten = rule.to.render(values) { return rewritten }
        }
        return segments
    }

    // MARK: - Private

    private static func placeholderNames(_ template: LYURLTemplate) -> Set<String> {
        Set(template.segments.compactMap { if case let .placeholder(name, _) = $0 { name } else { nil } })
    }
}
