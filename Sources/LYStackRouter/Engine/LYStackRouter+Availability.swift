#if canImport(UIKit)
    import Foundation

    public extension LYStackRouter {
        /// 检查静态处理能力，不执行拦截器、宿主操作或页面构造。最终结果由打开请求报告。
        func canOpen(_ route: Route, source: LYRouteSource = .user) -> Bool {
            staticFailure(route, source: source) == nil
        }

        /// 先重写并解析 URL，再检查静态处理能力。
        func canOpenURL(_ url: URL, source: LYRouteSource = .deepLink) -> Bool {
            guard let route = route(for: url) else { return false }
            return canOpen(route, source: source)
        }

        /// 参数校验应为纯判断；此处与实际提交共用同一顺序。
        internal func staticFailure(_ route: Route, source: LYRouteSource) -> LYRouteFailure? {
            guard !stopped else { return .stopped }
            guard let entry = registry.entries[route.kind] else {
                return allowsUnregistered && !source.isExternal && fallback != nil ? nil : .unregistered
            }
            if entry.policy.status == .disabled || rewrite.isDisabled(route.kind), fallback == nil { return .unavailable }
            if source.isExternal, !entry.policy.allowsExternal { return .notExternal }
            return entry.policy.validate(route) ? nil : .invalidParameter
        }
    }
#endif
