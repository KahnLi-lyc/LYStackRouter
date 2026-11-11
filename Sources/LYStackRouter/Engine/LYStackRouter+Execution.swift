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
            options: LYOpenOptions = .init(),
            _ operation: () -> Void
        ) -> Submission {
            let execution = NavigationExecution(sessionID: host?.routerSessionID, generation: generation)
            execution.options = options
            execution.targetNavigation = navigation(for: options)
            execution.isModal = execution.targetNavigation.map { !currentDomain.contains($0) } ?? false
            if execution.isModal, let navigation = execution.targetNavigation { adoptModalNavigation(navigation) }
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
            let transitions = executionDomain(execution).compactMap(\.transitionCoordinator)
            if preparation == nil, transitions.isEmpty, host?.routerRootViewController?.transitionCoordinator == nil {
                return Submission(immediate: complete(execution, intent: intent))
            }
            execution.completionTask = Task { [weak self] in
                await preparation?.value
                guard !Task.isCancelled, self?.isCurrent(execution) == true else { return }
                await self?.settleTransitions(execution)
                guard !Task.isCancelled, let self, isCurrent(execution) else { return }
                _ = complete(execution, intent: intent)
            }
            return Submission(immediate: execution.proposedResult, execution: execution)
        }

        /// 结算当前执行。外部请求在展示阶段被阻塞时重新进入等待。
        ///
        /// 刚受阻的请求等新的稳定事件（弹窗关闭、导航 `didShow`、转场完成或宿主调用 `navigationDidStabilize()`）再重试，
        /// 不在本次结算中立即消费，否则标准导航域看似空闲时会不断自我重放。执行期间到达的更新请求照常调度。
        func complete(_ execution: NavigationExecution, intent: Pending?) -> LYOpenResult {
            guard isCurrent(execution) else { return execution.result ?? .failed(.contextChanged) }
            detachConfirmationObservation()
            var result = execution.proposedResult
            var waitsForStabilization = false
            if result == .failed(.blocked), let intent {
                if pending == nil || pending!.sequence < intent.sequence {
                    pending = intent
                    waitsForStabilization = true
                }
                result = .deferred
            }
            currentExecution = nil
            _ = execution.takeWorkers()
            execution.finish(result)
            if waitsForStabilization, let pending {
                observeBlockingPresentation(for: placement(of: pending.route))
            } else {
                schedulePending()
            }
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
            // UIKit 可能省略最终回调，先移出登记并释放强快照；迟到回调仍可通过弱引用核对存活页面。
            let removals = Array(transitionRemovals.values)
            transitionRemovals.removeAll()
            removals.forEach { $0.invalidate() }
            managedNavigations.values.forEach { $0.detach() }
            managedNavigations.removeAll()
            let waiters = transitionWaiters.values
            transitionWaiters.removeAll()
            waiters.forEach { $0.resume() }
            modalObserver?.detach()
            modalObserver = nil
            pendingTransitionID = nil
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
            guard execution.isModal || host?.routerRootViewController?.presentedViewController == nil,
                  execution.hasCompletedTransition(host?.routerRootViewController?.transitionCoordinator),
                  executionDomain(execution).allSatisfy({ navigation in
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
            while !Task.isCancelled, isCurrent(execution), index < executionDomain(execution).count {
                let transition = executionDomain(execution)[index].transitionCoordinator
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
            return originNavigationIsCurrent(navigation) && source.parent != nil
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
            } onCancel: {
                // 在任务内弱引用：把外层弱捕获的变量再传进任务，Swift 6.3 会报 sending 'self' 数据竞争。
                Task { @MainActor [weak self] in self?.finishTransitionWait(id) }
            }
        }

        private func finishTransitionWait(_ id: UUID) {
            transitionWaiters.removeValue(forKey: id)?.resume()
        }

        /// 嵌套导航栈可继承同一转场；每次等待后重新读取，不重用已结束的协调器快照。
        private func settleTransitions(_ execution: NavigationExecution) async {
            var index = 0
            while index < executionDomain(execution).count {
                let coordinator = executionDomain(execution)[index].transitionCoordinator
                index += 1
                if let coordinator { await awaitTransition(coordinator) }
            }
        }

        // MARK: - Stabilization

        /// 宿主状态可能变化时调用（例如根视图就绪、弹窗关闭、会话恢复）：
        /// 核对准备中的执行来源是否仍有效，并尝试执行等待中的外部请求。
        public func navigationDidStabilize() {
            guard !stopped, host != nil else { return }
            if host?.isRouterReady != true { terminateExecution() }
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
            if let pending, !canNavigate(to: placement(of: pending.route), options: pending.options) { drainPendingAfterNavigationEvent() }
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

        /// 外部请求受阻时观察阻挡它的转场或弹窗，结束后重新尝试。
        ///
        /// 交互返回被取消时 UIKit 不保证再回调 `didShow`，因此转场必须单独观察完成，
        /// 否则转场期间到达的请求会一直等到下一次导航事件。
        func observeBlockingPresentation(for placement: LYRoutePlacement) {
            guard let host else { return }
            let domains = currentDomain + targetDomain(for: placement)
            if let transition = host.routerRootViewController?.transitionCoordinator
                ?? domains.lazy.compactMap(\.transitionCoordinator).first {
                observePendingTransition(transition)
            }
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

        /// 转场完成或取消后投递一次等待请求；UIKit 在完成回调之后才清除协调器，所以经由下一轮任务再尝试。
        private func observePendingTransition(_ transition: any UIViewControllerTransitionCoordinator) {
            let identity = ObjectIdentifier(transition as AnyObject)
            guard pendingTransitionID != identity else { return }
            pendingTransitionID = identity
            let epoch = generation
            let observed = transition.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self, pendingTransitionID == identity else { return }
                pendingTransitionID = nil
                guard isCurrent(epoch) else { return }
                drainPendingAfterNavigationEvent()
            }
            if !observed {
                pendingTransitionID = nil
                drainPendingAfterNavigationEvent()
            }
        }
    }
#endif
