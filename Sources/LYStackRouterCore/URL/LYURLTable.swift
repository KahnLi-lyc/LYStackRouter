import Foundation

/// 各模块登记的 URL 模板汇总，负责匹配与生成。
///
/// 多个模板同时匹配时，字面段多的优先；字面段数相同则按登记顺序。
/// 形状相同的模板在构建时已被拒绝，所以结果是确定的。
package struct LYURLTable<Route: LYRoutable>: Sendable {
    // MARK: - Properties

    package struct Entry: Sendable {
        package let template: LYURLTemplate
        package let moduleID: String
        package let parse: @Sendable (LYURLValues) -> Route?
        package let print: @Sendable (Route) -> LYURLValues?
    }

    package let entries: [Entry]

    // MARK: - Initialization

    /// 检查形状冲突后创建；冲突时抛出 `LYRouteBuildError.urlConflict`。
    package init(entries: [Entry]) throws {
        var firstByShape: [String: Entry] = [:]
        var conflicts: [String] = []
        for entry in entries {
            if let first = firstByShape[entry.template.shapeKey] {
                conflicts.append("\(first.template.raw)（\(first.moduleID)）与 \(entry.template.raw)（\(entry.moduleID)）")
            } else {
                firstByShape[entry.template.shapeKey] = entry
            }
        }
        guard conflicts.isEmpty else { throw LYRouteBuildError.urlConflict(conflicts) }
        // 稳定排序：先按具体程度，再保持登记顺序。
        self.entries = entries.enumerated()
            .sorted { lhs, rhs in
                lhs.element.template.literalCount != rhs.element.template.literalCount
                    ? lhs.element.template.literalCount > rhs.element.template.literalCount
                    : lhs.offset < rhs.offset
            }
            .map(\.element)
    }

    // MARK: - Internal

    /// 按路径段与 query 解析路由；模板匹配但 `parse` 拒绝时继续尝试下一个模板。
    package func route(segments: [String], query: [String: String]) -> Route? {
        for entry in entries {
            guard let path = entry.template.match(segments),
                  let route = entry.parse(LYURLValues(path: path, query: query)) else { continue }
            return route
        }
        return nil
    }

    /// 按模板排序列出所有能表达该路由的路径段与 query，供调用方逐个做往返校验。
    package func componentsCandidates(for route: Route) -> [(segments: [String], query: [String: String])] {
        entries.compactMap { entry in
            guard let values = entry.print(route), let segments = entry.template.render(values.path) else { return nil }
            return (segments, values.query)
        }
    }
}
