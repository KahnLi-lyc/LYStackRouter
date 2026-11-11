import DemoRouteContract
import LYStackRouter
import UIKit

/// 示例页面基类：标题、状态行（栈深度、清理数、最近结果）与一列按钮。
///
/// 标题标签的无障碍标识为 `page.<pageID>`，状态行为 `status.<pageID>`，供 UI 测试定位。
open class DemoPage: UIViewController, LYPageIdentifiable, LYRoutePageLifecycle {
    // MARK: - Properties

    /// 页面在 UI 测试中的标识，例如 `club.A`。
    public let pageID: String
    /// 业务身份；nil 表示每次打开都新建。
    public let identity: DemoPageIdentity?
    /// 共用观测数据。
    public let metrics: DemoMetrics
    /// 发起新的用户导航；由路由处理器或宿主注入。
    public var open: (DemoRoute) -> Void = { _ in }

    private var wasRemoved = false
    private let stack = UIStackView()
    private let statusLabel = UILabel()

    // MARK: - Initialization

    public init(pageID: String, title: String, identity: DemoPageIdentity?, metrics: DemoMetrics) {
        self.pageID = pageID
        self.identity = identity
        self.metrics = metrics
        super.init(nibName: nil, bundle: nil)
        self.title = title
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - View Lifecycle

    override open func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        stack.axis = .vertical
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor)
        ])
        let titleLabel = UILabel()
        titleLabel.text = pageID
        titleLabel.font = .preferredFont(forTextStyle: .headline)
        titleLabel.accessibilityIdentifier = "page.\(pageID)"
        stack.addArrangedSubview(titleLabel)
        statusLabel.font = .preferredFont(forTextStyle: .footnote)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0
        statusLabel.accessibilityIdentifier = "status.\(pageID)"
        stack.addArrangedSubview(statusLabel)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metricsDidChange),
            name: DemoMetrics.didChange,
            object: metrics
        )
    }

    override open func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        refreshStatus()
    }

    override open func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        refreshStatus()
    }

    // MARK: - LYPageIdentifiable

    public var routeIdentity: AnyHashable? {
        identity
    }

    // MARK: - LYRoutePageLifecycle

    open func routerDidRemovePage() {
        guard !wasRemoved else { return }
        wasRemoved = true
        NotificationCenter.default.removeObserver(self)
        metrics.pageWasRemoved()
    }

    // MARK: - Public

    /// 添加一个按钮，无障碍标识为 `id`。
    @discardableResult
    public func addButton(_ title: String, id: String, action: @escaping @MainActor () -> Void) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        let button = UIButton(configuration: configuration, primaryAction: UIAction { _ in action() })
        button.accessibilityIdentifier = id
        stack.addArrangedSubview(button)
        return button
    }

    /// 添加一段说明文字。
    public func addNote(_ text: String, id: String? = nil) {
        let label = UILabel()
        label.text = text
        label.numberOfLines = 0
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.accessibilityIdentifier = id
        stack.addArrangedSubview(label)
    }

    /// 刷新状态行：栈深度、已清理页面数与最近一次导航结果。
    public func refreshStatus() {
        let depth = navigationController?.viewControllers.firstIndex(of: self).map { $0 + 1 } ?? 0
        statusLabel.text = "depth \(depth) · cleaned \(metrics.cleanedPages) · last \(metrics.lastEvent)"
        statusLabel.accessibilityValue = metrics.recentEvents.joined(separator: " | ")
    }

    // MARK: - Private

    @objc
    private func metricsDidChange() {
        refreshStatus()
    }
}
