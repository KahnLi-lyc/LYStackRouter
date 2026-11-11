import Foundation

/// URL 入口的统一配置：哪些 scheme 与 Universal Link host 属于本 App。
///
/// - 自定义 scheme（如 `myapp://club/42`）：host 视为第一段路径，得到 `["club", "42"]`。
/// - Universal Link（如 `https://app.example.com/club/42`）：先校验 host 在白名单内，再只取路径，得到 `["club", "42"]`。
/// - 其他 scheme、非白名单 host、带重复 query 键或无值 query 的 URL 一律拒绝。
public struct LYURLConfiguration: Hashable, Sendable {
    // MARK: - Properties

    /// 本 App 的自定义 scheme，比较时不区分大小写。
    public var schemes: Set<String> {
        didSet { schemes = Set(schemes.map { $0.lowercased() }) }
    }

    /// 允许的 Universal Link host，比较时不区分大小写。
    public var universalLinkHosts: Set<String> {
        didSet { universalLinkHosts = Set(universalLinkHosts.map { $0.lowercased() }) }
    }

    /// 生成 URL 时使用的自定义 scheme；为 nil 时取按字母排序的第一个。
    public var preferredScheme: String? {
        didSet { preferredScheme = preferredScheme?.lowercased() }
    }

    // MARK: - Initialization

    /// 创建配置。
    public init(schemes: Set<String>, universalLinkHosts: Set<String> = [], preferredScheme: String? = nil) {
        self.schemes = Set(schemes.map { $0.lowercased() })
        self.universalLinkHosts = Set(universalLinkHosts.map { $0.lowercased() })
        self.preferredScheme = preferredScheme?.lowercased()
    }

    // MARK: - Internal

    /// 把 URL 拆成路径段与 query；不属于本 App 或 query 无效时返回 nil。
    package func components(of url: URL) -> (segments: [String], query: [String: String])? {
        guard let scheme = url.scheme?.lowercased() else { return nil }
        var segments: [String]
        if schemes.contains(scheme) {
            segments = url.host.map { [$0] } ?? []
            segments += url.pathComponents.filter { $0 != "/" }
        } else if scheme == "https", let host = url.host?.lowercased(), universalLinkHosts.contains(host) {
            segments = url.pathComponents.filter { $0 != "/" }
        } else {
            return nil
        }
        segments = segments.filter { !$0.isEmpty }
        guard !segments.isEmpty, let query = Self.query(of: url) else { return nil }
        return (segments, query)
    }

    /// 生成 URL。`universalLinkHost` 为 nil 时使用自定义 scheme。
    package func url(segments: [String], query: [String: String], universalLinkHost: String?) -> URL? {
        var components = URLComponents()
        if let universalLinkHost {
            guard universalLinkHosts.contains(universalLinkHost.lowercased()) else { return nil }
            components.scheme = "https"
            components.host = universalLinkHost.lowercased()
            components.path = "/" + segments.joined(separator: "/")
        } else {
            guard let scheme = preferredScheme ?? schemes.sorted().first, let first = segments.first else { return nil }
            components.scheme = scheme
            components.host = first
            let rest = segments.dropFirst()
            components.path = rest.isEmpty ? "" : "/" + rest.joined(separator: "/")
        }
        if !query.isEmpty {
            components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        return components.url
    }

    // MARK: - Private

    private static func query(of url: URL) -> [String: String]? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        var result: [String: String] = [:]
        for item in items {
            guard let value = item.value, result[item.name] == nil else { return nil }
            result[item.name] = value
        }
        return result
    }
}
