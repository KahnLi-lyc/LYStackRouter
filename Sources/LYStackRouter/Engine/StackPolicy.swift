/// 针对目标页面的最小栈操作。
enum StackDecision: Equatable {
    /// 目标已在栈顶。
    case alreadyTop
    /// 回到最近的同身份页面，索引对应输入栈的位置。
    case popTo(index: Int)
    /// 栈内没有目标，需要创建页面。
    case push
}

/// 只比较业务身份的栈策略；导航执行与页面清理由引擎负责。
enum StackPolicy {
    /// 从栈尾查找最近的同身份页面；没有身份的页面不参与匹配，但占据原始索引。
    static func decide(target: AnyHashable, stack: [AnyHashable?]) -> StackDecision {
        guard let index = stack.lastIndex(where: { $0 == target }) else { return .push }
        return index == stack.indices.last ? .alreadyTop : .popTo(index: index)
    }
}
