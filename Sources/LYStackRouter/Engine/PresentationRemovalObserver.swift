#if canImport(UIKit)
    import UIKit

    /// 观察一个弹窗的 presentation 容器离开窗口，用于在弹窗关闭后重新尝试等待中的请求。
    ///
    /// 只在容器里放一个不可交互、不可访问的空视图，不替换 presentation delegate，
    /// 因此不影响 `UIAlertController` 与业务自己的 delegate。容器尚未创建时，等待这一次真实转场结束再挂。
    @MainActor
    final class PresentationRemovalObserver {
        // MARK: - Properties

        weak var presentation: UIPresentationController?
        private let removalView = PresentationRemovalView()
        private var isDetached = false

        // MARK: - Initialization

        init(presentation: UIPresentationController, onRemoved: @escaping @MainActor () -> Void) {
            self.presentation = presentation
            removalView.onRemoved = { [weak self] in
                guard let self else { return }
                detach()
                onRemoved()
            }
            attachIfAvailable()
            if removalView.superview == nil,
               let transition = presentation.presentedViewController.transitionCoordinator
               ?? presentation.presentingViewController.transitionCoordinator {
                if !transition.animate(alongsideTransition: nil, completion: { [weak self] _ in self?.attachIfAvailable() }) {
                    attachIfAvailable()
                }
            }
        }

        // MARK: - Teardown

        /// 先撤回调再移除视图；重复调用安全。
        func detach() {
            isDetached = true
            removalView.onRemoved = nil
            removalView.removeFromSuperview()
        }

        // MARK: - Private

        private func attachIfAvailable() {
            guard !isDetached, removalView.superview == nil, let container = presentation?.containerView else { return }
            container.addSubview(removalView)
        }
    }

    /// 只观察自身离开窗口，不参与布局与交互。
    @MainActor
    final class PresentationRemovalView: UIView {
        // MARK: - Properties

        var onRemoved: (@MainActor () -> Void)?
        private var wasInWindow = false

        // MARK: - Initialization

        override init(frame: CGRect) {
            super.init(frame: frame)
            isUserInteractionEnabled = false
            isAccessibilityElement = false
            isHidden = true
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        // MARK: - View Lifecycle

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window != nil {
                wasInWindow = true
            } else if wasInWindow {
                wasInWindow = false
                Task { [weak self] in self?.onRemoved?() }
            }
        }
    }
#endif
