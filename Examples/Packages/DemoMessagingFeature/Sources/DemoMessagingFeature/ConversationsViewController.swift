import DemoRouteContract
import DemoUIKit
import LYStackRouter
import UIKit

/// 会话容器把详情放入独立导航栈，宿主将两个栈声明为同一导航域。
public final class ConversationsViewController: DemoPage {
    // MARK: - Properties

    /// 详情导航栈，供宿主接入导航事件和准备期校验。
    public let detailNavigation = UINavigationController()
    private let detailContainer = UIView()
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
        addChild(detailNavigation)
        detailNavigation.view.translatesAutoresizingMaskIntoConstraints = false
        detailContainer.addSubview(detailNavigation.view)
        NSLayoutConstraint.activate([
            detailNavigation.view.topAnchor.constraint(equalTo: detailContainer.topAnchor),
            detailNavigation.view.leadingAnchor.constraint(equalTo: detailContainer.leadingAnchor),
            detailNavigation.view.trailingAnchor.constraint(equalTo: detailContainer.trailingAnchor),
            detailNavigation.view.bottomAnchor.constraint(equalTo: detailContainer.bottomAnchor)
        ])
        detailNavigation.didMove(toParent: self)
    }

    // MARK: - Public

    /// 展示详情；相同身份回到现有详情，替换时只清理离开详情栈的页面。
    public func showDetail(identity: AnyHashable?, animated: Bool = true, make: () -> UIViewController) -> LYOpenResult {
        loadViewIfNeeded()
        if let identity, identity == detailIdentity, let existing = detailNavigation.viewControllers.first {
            if detailNavigation.topViewController === existing { return .alreadyVisible }
            let removed = Array(detailNavigation.viewControllers.dropFirst())
            detailNavigation.setViewControllers([existing], animated: animated && detailNavigation.viewIfLoaded?.window != nil)
            cleanAfterTransition(removed)
            return .reused
        }
        let removed = detailNavigation.viewControllers
        let page = make()
        detailNavigation.setViewControllers([page], animated: animated && detailNavigation.viewIfLoaded?.window != nil)
        cleanAfterTransition(removed)
        detailIdentity = identity
        return .created
    }

    // MARK: - Private

    private func cleanAfterTransition(_ removed: [UIViewController]) {
        let cleanup: @MainActor () -> Void = { [weak self] in
            guard let self else { return }
            for page in removed where !detailNavigation.viewControllers.contains(where: { $0 === page }) && page.parent == nil {
                (page as? LYRoutePageLifecycle)?.routerDidRemovePage()
            }
        }
        if let transition = detailNavigation.transitionCoordinator {
            if !transition.animate(alongsideTransition: nil, completion: { _ in cleanup() }) { cleanup() }
        } else {
            cleanup()
        }
    }
}
