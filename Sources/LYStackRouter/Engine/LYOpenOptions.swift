#if canImport(UIKit)
    import UIKit

    /// 一次打开请求的展示选项；业务参数由类型化路由携带。
    @MainActor
    public struct LYOpenOptions {
        /// 是否使用导航动画。
        public var animated: Bool
        /// 弱引用的来源页面；显式来源失效后请求不会改用其它页面。
        public private(set) weak var from: UIViewController?
        /// 跨切面附加值，不参与 URL 解析或参数覆盖，也不会自动写入日志。
        public var extras: [String: any Sendable]
        let hasExplicitOrigin: Bool

        /// 创建打开选项。请避免在附加值中持有页面、Store 或长生命周期资源。
        public init(animated: Bool = true, from: UIViewController? = nil, extras: [String: any Sendable] = [:]) {
            self.animated = animated
            self.from = from
            self.extras = extras
            hasExplicitOrigin = from != nil
        }
    }
#endif
