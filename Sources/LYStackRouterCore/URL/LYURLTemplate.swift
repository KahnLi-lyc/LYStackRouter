/// 占位符的取值类型。
public enum LYURLPlaceholderType: String, Hashable, Sendable {
    /// 任意非空段。
    case string
    /// 十进制整数段。
    case int
    /// 剩余的全部段，只能出现在模板末尾。
    case path
}

/// 解析后的路径模板，例如 `club/<clubID>`、`user/<int:id>`、`web/<path:rest>`。
///
/// 模板只描述路径；scheme 与 Universal Link host 由 `LYURLConfiguration` 统一处理。
package struct LYURLTemplate: Hashable, Sendable {
    // MARK: - Properties

    package enum Segment: Hashable, Sendable {
        case literal(String)
        case placeholder(name: String, type: LYURLPlaceholderType)
    }

    package let raw: String
    package let segments: [Segment]

    // MARK: - Initialization

    /// 解析模板；写法无效时抛出 `LYRouteBuildError.invalidURLPattern`。
    package init(_ raw: String) throws {
        let parts = raw.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { throw LYRouteBuildError.invalidURLPattern("\(raw)：模板为空") }
        var names = Set<String>()
        var segments: [Segment] = []
        for (index, part) in parts.enumerated() {
            guard part.hasPrefix("<"), part.hasSuffix(">") else {
                guard !part.contains("<"), !part.contains(">") else {
                    throw LYRouteBuildError.invalidURLPattern("\(raw)：占位符必须独占一段")
                }
                segments.append(.literal(part))
                continue
            }
            let body = part.dropFirst().dropLast()
            let pieces = body.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            let (typeName, name): (String, String) = switch pieces.count {
            case 1: ("string", pieces[0])
            case 2: (pieces[0], pieces[1])
            default: ("", "")
            }
            guard let type = LYURLPlaceholderType(rawValue: typeName), Self.isValidName(name) else {
                throw LYRouteBuildError.invalidURLPattern("\(raw)：无效的占位符 \(part)")
            }
            guard names.insert(name).inserted else {
                throw LYRouteBuildError.invalidURLPattern("\(raw)：占位名 \(name) 重复")
            }
            guard type != .path || index == parts.count - 1 else {
                throw LYRouteBuildError.invalidURLPattern("\(raw)：path 占位符只能在末尾")
            }
            segments.append(.placeholder(name: name, type: type))
        }
        self.raw = raw
        self.segments = segments
    }

    // MARK: - Internal

    /// 字面段数量，用于在多个模板同时匹配时选择更具体的一个。
    package var literalCount: Int {
        segments.count { if case .literal = $0 { true } else { false } }
    }

    /// 形状标识：字面段保留原文，占位符折叠为通配。形状相同的两个模板无法区分，视为冲突。
    package var shapeKey: String {
        segments.map { segment in
            switch segment {
            case let .literal(value): value
            case let .placeholder(_, type): type == .path ? "**" : "*"
            }
        }.joined(separator: "/")
    }

    /// 匹配路径段，成功时返回占位符取值。
    package func match(_ input: [String]) -> [String: String]? {
        let hasPathTail = if case .placeholder(_, .path) = segments.last { true } else { false }
        if hasPathTail ? input.count < segments.count : input.count != segments.count { return nil }
        var values: [String: String] = [:]
        for (index, segment) in segments.enumerated() {
            switch segment {
            case let .literal(value):
                guard input[index] == value else { return nil }
            case let .placeholder(name, type):
                switch type {
                case .string:
                    values[name] = input[index]
                case .int:
                    guard Int(input[index]) != nil else { return nil }
                    values[name] = input[index]
                case .path:
                    values[name] = input[index...].joined(separator: "/")
                }
            }
        }
        return values
    }

    /// 用取值生成路径段；缺少取值或类型不符时返回 nil。
    package func render(_ values: [String: String]) -> [String]? {
        var output: [String] = []
        for segment in segments {
            switch segment {
            case let .literal(value):
                output.append(value)
            case let .placeholder(name, type):
                guard let value = values[name], !value.isEmpty else { return nil }
                switch type {
                case .string:
                    guard !value.contains("/") else { return nil }
                    output.append(value)
                case .int:
                    guard Int(value) != nil else { return nil }
                    output.append(value)
                case .path:
                    output.append(contentsOf: value.split(separator: "/").map(String.init))
                }
            }
        }
        return output
    }

    // MARK: - Private

    private static func isValidName(_ name: String) -> Bool {
        !name.isEmpty && name.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }
}
