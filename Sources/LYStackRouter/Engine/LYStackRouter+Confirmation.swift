#if canImport(UIKit)
    import UIKit

    extension LYStackRouter {
        // MARK: - Confirmation Gate

        /// 确认框真正展示完成：以 `.awaitingConfirmation` 结算，释放执行权。旧回调不能结算后来的执行。
        func confirmationDidPresent(_ execution: NavigationExecution) {
            guard isCurrent(execution), execution.phase == .presenting,
                  execution.proposedResult == .awaitingConfirmation else { return }
            guard originIsCurrent(execution) else {
                terminateExecution()
                return
            }
            _ = complete(execution, intent: nil)
        }

        /// 确认框被 UIKit 拒绝展示或在完成前被移除：以 `.blocked` 结算，避免执行权一直被占用。
        func confirmationDidFailToPresent(_ execution: NavigationExecution) {
            guard isCurrent(execution), execution.proposedResult == .awaitingConfirmation else { return }
            execution.proposedResult = .failed(.blocked)
            _ = complete(execution, intent: nil)
        }

        /// 观察确认框容器被移除；容器可能稍后才创建，此时只等这一次真实展示转场。
        func observeConfirmationRemoval(_ alert: UIAlertController, execution: NavigationExecution) {
            guard isCurrent(execution), execution.proposedResult == .awaitingConfirmation else { return }
            if installConfirmationRemoval(alert, execution: execution) { return }
            guard let transition = alert.transitionCoordinator ?? execution.navigation?.transitionCoordinator else { return }
            execution.completionTask = Task { [weak self, weak execution, weak alert] in
                guard let self else { return }
                await awaitTransition(transition)
                guard !Task.isCancelled, let execution, let alert, isCurrent(execution) else { return }
                _ = installConfirmationRemoval(alert, execution: execution)
            }
        }

        @discardableResult
        private func installConfirmationRemoval(_ alert: UIAlertController, execution: NavigationExecution) -> Bool {
            guard isCurrent(execution), execution.proposedResult == .awaitingConfirmation,
                  let container = alert.presentationController?.containerView else { return false }
            detachConfirmationObservation()
            let observation = PresentationRemovalView()
            observation.onRemoved = { [weak self, weak execution, weak alert] in
                guard let self, let execution, isCurrent(execution) else { return }
                execution.completionTask = Task { [weak self, weak execution, weak alert] in
                    guard let self, let execution, isCurrent(execution) else { return }
                    if let transition = alert?.transitionCoordinator { await awaitTransition(transition) }
                    guard !Task.isCancelled, isCurrent(execution), alert?.presentingViewController == nil,
                          alert?.viewIfLoaded?.window == nil else { return }
                    confirmationDidFailToPresent(execution)
                }
            }
            confirmationObservation = observation
            container.addSubview(observation)
            return true
        }

        func detachConfirmationObservation() {
            confirmationObservation?.onRemoved = nil
            confirmationObservation?.removeFromSuperview()
            confirmationObservation = nil
        }

        /// 确认框结算后，确认回调是否仍属于当前代次与会话。不要求执行仍是当前执行：确认框展示完成时它已结算。
        func isConfirmationContextValid(_ execution: NavigationExecution) -> Bool {
            isCurrent(execution.generation) && execution.sessionID == host?.routerSessionID
        }

        /// 确认后的后续导航前核对：来源仍在栈顶、没有弹窗、没有转场。
        func isOriginStillPresented(_ navigation: UINavigationController, source: UIViewController) -> Bool {
            !stopped && host != nil && currentDomain.contains { $0 === navigation }
                && navigation.topViewController === source && source.parent != nil
                && Self.isIdle(navigation) && source.presentedViewController == nil
                && host?.routerRootViewController?.presentedViewController == nil
        }
    }
#endif
