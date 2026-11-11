#if canImport(UIKit)
    import UIKit

    /// 一次栈操作的移出页面快照。失效时释放强引用，迟到回调仅检查仍存活的弱引用页面。
    ///
    /// 原宿主使用弱引用；宿主释放后仍直接通知页面生命周期。
    /// 自定义宿主如需执行额外清理，应保持存活至对应转场结束。
    @MainActor
    final class StackRemoval {
        private weak var owner: (any LYRouterHost)?
        private var retainedPages: [UIViewController]
        private let references: [PageReference]
        private var cleaned = Set<ObjectIdentifier>()
        private var isFinished = false

        init(pages: [UIViewController], owner: (any LYRouterHost)?) {
            var identities = Set<ObjectIdentifier>()
            let uniquePages = pages.filter { identities.insert(ObjectIdentifier($0)).inserted }
            self.owner = owner
            retainedPages = uniquePages
            references = uniquePages.map { PageReference(page: $0) }
        }

        /// 执行完成后只清理确实脱离展示树的页面；重复完成通知无副作用。
        func complete(in navigation: UINavigationController?) {
            guard !isFinished else { return }
            isFinished = true
            cleanDetachedPages(excluding: navigation)
            retainedPages.removeAll()
        }

        /// 路由器关闭模态栈后清理：仍挂在已关闭导航栈上的页面与已脱离展示树的页面都属于本次退出。
        func completeDismissal(of navigation: UINavigationController?) {
            guard !isFinished else { return }
            isFinished = true
            cleanDetachedPages(excluding: nil, dismissed: navigation)
            retainedPages.removeAll()
        }

        /// 不依赖 UIKit 最终回调释放页面；仍有归属的页面可由迟到回调再次核对。
        func invalidate() {
            guard !isFinished else { return }
            cleanDetachedPages(excluding: nil)
            retainedPages.removeAll()
        }

        private func cleanDetachedPages(excluding navigation: UINavigationController?, dismissed: UINavigationController? = nil) {
            for reference in references {
                guard let page = reference.page, !cleaned.contains(reference.identity),
                      navigation?.viewControllers.contains(where: { $0 === page }) != true,
                      isDetached(page, dismissed: dismissed) else { continue }
                // 先标记，清理回调同步触发重置或重复完成时也只通知一次。
                cleaned.insert(reference.identity)
                if let owner { owner.tearDown(page) }
                else { (page as? LYRoutePageLifecycle)?.routerDidRemovePage() }
            }
        }

        /// 已关闭且不再展示的导航栈中的页面视为脱离；其余页面必须没有父容器、展示关系与窗口。
        private func isDetached(_ page: UIViewController, dismissed: UINavigationController?) -> Bool {
            if let dismissed, page.parent === dismissed {
                return dismissed.presentingViewController == nil && dismissed.viewIfLoaded?.window == nil
            }
            return page.parent == nil && page.presentingViewController == nil && page.viewIfLoaded?.window == nil
        }

        private struct PageReference {
            weak var page: UIViewController?
            let identity: ObjectIdentifier

            init(page: UIViewController) {
                self.page = page
                identity = ObjectIdentifier(page)
            }
        }
    }
#endif
