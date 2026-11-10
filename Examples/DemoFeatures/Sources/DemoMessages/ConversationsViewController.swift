import DemoRoutes
import LYStackRouter
import UIKit

/// 消息 Tab 的根容器：上方会话列表，下方嵌入当前私信（宽屏时左右排布）。
///
/// 宿主在 `customShow` 中把私信交给 `showDetail`，路由器因此不会再 push。
public final class ConversationsViewController: DemoPage {
    // MARK: - Properties

    private let detailContainer = UIView()
    private var detail: UIViewController?
    private var detailIdentity: AnyHashable?

    // MARK: - Initialization

    public init(metrics: DemoMetrics) {
        super.init(pageID: "conversations", title: "消息", identity: nil, metrics: metrics)
    }

    // MARK: - View Lifecycle

    override public func viewDidLoad() {
        super.viewDidLoad()
        addButton("会话 c1", id: "open.chat.c1") { [weak self] in self?.open(.chat("c1")) }
        addButton("会话 c2", id: "open.chat.c2") { [weak self] in self?.open(.chat("c2")) }
        detailContainer.backgroundColor = .secondarySystemBackground
        detailContainer.layer.cornerRadius = 12
        detailContainer.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.accessibilityIdentifier = "conversations.detail"
        view.addSubview(detailContainer)
        NSLayoutConstraint.activate([
            detailContainer.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            detailContainer.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            detailContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            detailContainer.heightAnchor.constraint(equalTo: view.safeAreaLayoutGuide.heightAnchor, multiplier: 0.5)
        ])
    }

    // MARK: - Public

    /// 把私信嵌入详情区。同一身份已在详情区时返回 `.alreadyVisible`；替换出的旧私信收到清理通知。
    public func showDetail(identity: AnyHashable?, make: () -> UIViewController) -> LYOpenResult {
        if let identity, identity == detailIdentity { return .alreadyVisible }
        if let old = detail {
            old.willMove(toParent: nil)
            old.view.removeFromSuperview()
            old.removeFromParent()
            (old as? LYRoutePageLifecycle)?.routerDidRemovePage()
        }
        let page = make()
        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(page.view)
        NSLayoutConstraint.activate([
            page.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            page.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            page.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            page.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
        ])
        page.didMove(toParent: self)
        detail = page
        detailIdentity = identity
        return .created
    }
}
