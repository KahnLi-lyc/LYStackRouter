#if canImport(UIKit)
    import UIKit

    /// 触发兜底的原因。
    public enum LYRouteFallbackReason: Hashable, Sendable {
        /// 没有模块注册该路由（只在非穷尽构建时出现，例如模块 Demo）。
        case unregistered
        /// 路由登记为占位状态。
        case placeholder
        /// 路由被禁用或被远程配置降级。
        case unavailable
    }

    /// 未注册、占位或降级时的统一兜底。兜底在一次正常的导航执行内运行，可以展示页面。
    @MainActor
    public struct LYRouteFallback<Route: LYRoutable> {
        // MARK: - Properties

        let handle: @MainActor (Route, LYRouteFallbackReason, LYRouteContext<Route>) -> Void

        // MARK: - Initialization

        /// 自定义兜底，例如打开 H5 或记录日志。
        public init(_ handle: @escaping @MainActor (Route, LYRouteFallbackReason, LYRouteContext<Route>) -> Void) {
            self.handle = handle
        }

        // MARK: - Public

        /// 推入一个显示路由种类与原因的占位页，适合模块 Demo 与开发阶段。
        public static var placeholder: LYRouteFallback {
            LYRouteFallback { route, reason, context in
                context.show {
                    LYRoutePlaceholderViewController(title: "\(route.kind)", detail: "\(reason)")
                }
            }
        }
    }

    /// 兜底占位页，只展示标题与原因。
    @MainActor
    public final class LYRoutePlaceholderViewController: UIViewController {
        // MARK: - Properties

        private let detail: String

        // MARK: - Initialization

        /// 创建占位页。
        public init(title: String, detail: String) {
            self.detail = detail
            super.init(nibName: nil, bundle: nil)
            self.title = title
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        // MARK: - View Lifecycle

        override public func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .systemBackground
            let label = UILabel()
            label.text = "\(title ?? "")\n\(detail)"
            label.numberOfLines = 0
            label.textAlignment = .center
            label.accessibilityIdentifier = "LYRoutePlaceholder"
            label.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: view.layoutMarginsGuide.leadingAnchor)
            ])
        }
    }
#endif
