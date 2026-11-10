#if canImport(UIKit)
    import UIKit

    extension LYStackRouter {
        // MARK: - Execution

        /// 取得执行权并同步运行操作。没有异步准备和转场时立即结算，否则等待它们完成后结算。
        /// `kind` 为 nil 表示非路由操作（例如返回），不通知观察者。
        func execute(
            kind: Route.Kind?,
            source: LYRouteSource,
            intent: Pending?,
            proposed: LYOpenResult,
            _ operation: () -> Void
        ) -> Submission {
            let execution = NavigationExecution(sessionID: host?.routerSessionID, generation: generation)
            execution.proposedResult = proposed
            if let kind {
                execution.onFinish = { [weak self] result in self?.notifySettle(kind, source: source, result: result) }
            }
            currentExecution = execution
            operation()
            // 测试或自定义展示可能同步回调；已经结算的结果仍属于本次执行。
            guard isCurrent(execution) else { return Submission(immediate: execution.result ?? .failed(.contextChanged)) }
            if execution.proposedResult == .awaitingConfirmation {
                // 确认框只在真实展示完成时结算。
                return Submission(immediate: .awaitingConfirmation, execution: execution)
            }
            let preparation = execution.preparationTask
            let transitions = currentDomain.compactMap(\.transitionCoordinator)
            if preparation == nil, transitions.isEmpty, host?.routerRootViewController?.transitionCoordinator == nil {
                return Submission(immediate: complete(execution, intent: intent))
            }
            execution.completionTask = Task { [weak self] in
                await preparation?.value
                guard !Task.isCancelled, self?.isCurrent(execution) == true else { return }
                await self?.settleTransitions()
                guard !Task.isCancelled, let self, isCurrent(execution) else { return }
                _ = complete(execution, intent: intent)
            }
            return Submission(immediate: execution.proposedResult, execution: execution)
        }

        /// 结算当前执行。外部请求在展示阶段被阻塞时重新进入等待。
        func complete(_ execution: NavigationExecution, intent: Pending?) -> LYOpenResult {
            guard isCurrent(execution) else { return execution.result ?? .failed(.contextChanged) }
            detachConfirmationObservation()
            var result = execution.proposedResult
            if result == .failed(.blocked), let intent {
                if pending == nil || pending!.sequence < intent.sequence { pending = intent }
                result = .deferred
            }
            currentExecution = nil
            _ = execution.takeWorkers()
            execution.finish(result)
            schedulePending()
            return result
        }

        /// 不等待底层任务响应取消；旧执行与其任务同步脱离执行权。
        func terminateExecution() {
            guard let execution = currentExecution else { return }
            detachConfirmationObservation()
            currentExecution = nil
            let workers = execution.takeWorkers()
            execution.finish(.failed(.contextChanged))
            workers.forEach { $0.cancel() }
        }

        /// 使当前代次失效：终止执行、清理挂起的移出页面、唤醒全部转场等待。
        func invalidateExecution() {
            terminateExecution()
            generation = UUID()
            let removals = transitionRemovals.values.flatMap(\.self)
            transitionRemovals.removeAll()
            removals.forEach { host?.tearDown($0) }
            let waiters = transitionWaiters.values
            transitionWaiters.removeAll()
            waiters.forEach { $0.resume() }
            modalObserver?.detach()
            modalObserver = nil
        }

        func isCurrent(_ token: UUID) -> Bool {
            generation == token && !stopped && host != nil
        }

        func isCurrent(_ execution: NavigationExecution) -> Bool {
            currentExecution === execution && execution.result == nil
                && execution.sessionID == host?.routerSessionID && isCurrent(execution.generation)
        }

        func markResult(_ value: LYOpenResult) {
            currentExecution?.proposedResult = value
        }

        // MARK: - Preparation

        /// 绑定异步准备的来源页面；之后只有来源仍在栈顶才继续展示。
        func bindOrigin(source: UIViewController, navigation: UINavigationController) -> NavigationExecution? {
            guard let execution = currentExecution, isCurrent(execution) else { return nil }
            execution.bind(source: source, navigation: navigation)
            return execution
        }

        /// 异步准备返回后检查：执行仍有效、来源仍在栈顶、没有弹窗或未完成的转场。
        func validateContinuation(_ execution: NavigationExecution) async -> Bool {
            guard !Task.isCancelled, isCurrent(execution) else { return false }
            // 交互返回中的 top/parent 是临时值；只在转场真正完成或取消后判断。
            await awaitPreparationTransitions(execution)
            guard !Task.isCancelled, isCurrent(execution) else { return false }
            guard host?.isRouterReady == true, originIsCurrent(execution) else {
                markResult(.failed(.contextChanged))
                return false
            }
            guard host?.routerRootViewController?.presentedViewController == nil,
                  execution.hasCompletedTransition(host?.routerRootViewController?.transitionCoordinator),
                  currentDomain.allSatisfy({ navigation in
                      execution.hasCompletedTransition(navigation.transitionCoordinator)
                          && navigation.presentedViewController == nil
                          && navigation.topViewController?.presentedViewController == nil
                  }) else {
                markResult(.failed(.blocked))
                return false
            }
            return true
        }

        /// 每次等待后重新读取当前协调器；不跨挂起点持有页面或导航栈。
        private func awaitPreparationTransitions(_ execution: NavigationExecution) async {
            if let transition = host?.routerRootViewController?.transitionCoordinator,
               !execution.hasCompletedTransition(transition) {
                await awaitTransition(transition)
                guard !Task.isCancelled, isCurrent(execution) else { return }
                execution.rememberCompletedTransition(transition)
            }
            guard !Task.isCancelled, isCurrent(execution) else { return }
            if let transition = execution.navigation?.transitionCoordinator, !execution.hasCompletedTransition(transition) {
                await awaitTransition(transition)
                guard !Task.isCancelled, isCurrent(execution) else { return }
                execution.rememberCompletedTransition(transition)
            }
            var index = 0
            while !Task.isCancelled, isCurrent(execution), index < currentDomain.count {
                let transition = currentDomain[index].transitionCoordinator
                index += 1
                if let transition, !execution.hasCompletedTransition(transition) {
                    await awaitTransition(transition)
                    guard !Task.isCancelled, isCurrent(execution) else { return }
                    execution.rememberCompletedTransition(transition)
                }
            }
        }

        func originIsCurrent(_ execution: NavigationExecution) -> Bool {
            guard let navigation = execution.navigation, let source = execution.source else { return false }
            return currentDomain.contains { $0 === navigation } && source.parent != nil
                && navigation.topViewController === source
        }

        // MARK: - Transitions

        func awaitTransition(_ coordinator: any UIViewControllerTransitionCoordinator) async {
            await awaitUICompletion { completion in
                if !coordinator.animate(alongsideTransition: nil, completion: { _ in completion() }) { completion() }
            }
        }

        /// UIKit 可能因根被移除而省略完成回调；解绑和任务取消也必须结束等待。
        func awaitUICompletion(_ start: (@escaping @MainActor () -> Void) -> Void) async {
            let id = UUID()
            await withTaskCancellationHandler {
                guard !Task.isCancelled else { return }
                await withCheckedContinuation { continuation in
                    transitionWaiters[id] = continuation
                    start { [weak self] in self?.finishTransitionWait(id) }
                }
            } onCancel: { [weak self] in
                Task { @MainActor in self?.finishTransitionWait(id) }
            }
        }

        private func finishTransitionWait(_ id: UUID) {
            transitionWaiters.removeValue(forKey: id)?.resume()
        }

        /// 嵌套导航栈可继承同一转场；每次等待后重新读取，不重用已结束的协调器快照。
        private func settleTransitions() async {
            var index = 0
            while index < currentDomain.count {
                let coordinator = currentDomain[index].transitionCoordinator
                index += 1
                if let coordinator { await awaitTransition(coordinator) }
            }
        }

        // MARK: - Stabilization

        /// 宿主状态可能变化时调用（例如根视图就绪、弹窗关闭、会话恢复）：
        /// 核对准备中的执行来源是否仍有效，并尝试执行等待中的外部请求。
        public func navigationDidStabilize() {
            guard !stopped, host != nil else { return }
            if let execution = currentExecution, execution.phase == .preparing, execution.hasOrigin {
                if let transition = host?.routerRootViewController?.transitionCoordinator
                    ?? execution.navigation?.transitionCoordinator {
                    let identity = ObjectIdentifier(transition as AnyObject)
                    if execution.observedTransitionID != identity {
                        execution.observedTransitionID = identity
                        let epoch = generation
                        // 只观察真实完成；取消时 UIKit 可能仍在恢复原栈，交给真实 didShow 再核对。
                        _ = transition.animate(alongsideTransition: nil) { [weak self, weak execution] context in
                            guard let self, isCurrent(epoch) else { return }
                            if !context.isCancelled, let execution, isCurrent(execution) { reconcileStableOrigin() }
                            drainPendingAfterNavigationEvent()
                        }
                    }
                } else if !originIsCurrent(execution) {
                    terminateExecution()
                }
            }
            schedulePending()
            if let pending, !canNavigate(to: placement(of: pending.route)) { drainPendingAfterNavigationEvent() }
        }

        /// 宿主在导航栈的 `didShow` 回调中调用：UIKit 已确认完成或取消，可核对真实来源。
        public func navigationDidShow(in navigation: UINavigationController) {
            guard !stopped, host != nil else { return }
            if currentExecution?.navigation === navigation { reconcileStableOrigin() }
            navigationDidStabilize()
        }

        private func reconcileStableOrigin() {
            guard let execution = currentExecution, execution.phase == .preparing,
                  execution.hasOrigin, !originIsCurrent(execution) else { return }
            terminateExecution()
        }

        /// 外部请求被弹窗挡住时，观察该弹窗离开窗口，然后重新尝试。
        func observeBlockingPresentation(for placement: LYRoutePlacement) {
            guard let host else { return }
            let domains = currentDomain + targetDomain(for: placement)
            let presenters = [host.routerRootViewController].compactMap(\.self)
                + domains.flatMap { [$0 as UIViewController] + $0.viewControllers }
            guard var presented = presenters.compactMap(\.presentedViewController).first else { return }
            while let next = presented.presentedViewController {
                presented = next
            }
            guard let presentation = presented.presentationController else { return }
            if modalObserver?.presentation === presentation { return }
            modalObserver?.detach()
            modalObserver = PresentationRemovalObserver(presentation: presentation) { [weak self] in
                self?.navigationDidStabilize()
            }
        }
    }
#endif
