#if canImport(UIKit)
    import UIKit

    extension LYStackRouter {
        // MARK: - Submission

        /// 同步准入的结果：立即结果，以及需要等待时的执行。
        struct Submission {
            let immediate: LYOpenResult
            var execution: NavigationExecution?
        }

        /// 所有路由请求的入口。准入顺序：停止 → 注册 → 禁用 → 外部白名单 → 校验 → 拦截 → 宿主状态 → 执行。
        /// 准入在切换目标域、创建页面等任何副作用之前完成。
        func submit(_ route: Route, source: LYRouteSource) -> Submission {
            let kind = route.kind
            guard !stopped else { return settled(kind, source, .failed(.stopped)) }

            guard let entry = registry.entries[kind] else {
                guard allowsUnregistered, let fallback else { return settled(kind, source, .failed(.unregistered)) }
                return admit(route, source, placement: .current, proposed: .failed(.unregistered)) { context in
                    fallback.handle(route, .unregistered, context)
                }
            }
            if entry.policy.status == .disabled || rewrite.isDisabled(kind) {
                guard let fallback else { return settled(kind, source, .failed(.unavailable)) }
                return admit(route, source, placement: .current, proposed: .failed(.unavailable)) { context in
                    fallback.handle(route, .unavailable, context)
                }
            }
            if source.isExternal, !entry.policy.allowsExternal { return settled(kind, source, .failed(.notExternal)) }
            guard entry.policy.validate(route) else { return settled(kind, source, .failed(.invalidParameter)) }

            let request = LYInterceptRequest(
                route: route,
                source: source,
                policyRequiresSession: entry.policy.requiresSession
            )
            switch LYRouteInterceptor.evaluate(interceptors, request: request) {
            case .proceed:
                break
            case let .reject(failure):
                return settled(kind, source, .failed(failure))
            case let .redirect(target):
                // 重定向后的路由重新经过完整准入；限制深度，避免拦截器互相重定向形成死循环。
                guard redirectDepth < 4 else { return settled(kind, source, .failed(.rejected("redirectLoop"))) }
                redirectDepth += 1
                defer { redirectDepth -= 1 }
                return submit(target, source: source)
            case .deferUntilReady:
                return deferOrIgnore(route, source, placement: entry.policy.placement)
            }

            if entry.policy.status == .placeholder, let fallback {
                return admit(route, source, placement: entry.policy.placement, proposed: .failed(.unavailable)) { context in
                    fallback.handle(route, .placeholder, context)
                }
            }
            let proposed: LYOpenResult = entry.handlerKind == .action ? .performed : .failed(.unavailable)
            return admit(route, source, placement: entry.policy.placement, proposed: proposed) { context in
                entry.handle(route, context)
            }
        }

        /// 宿主状态准入后开始执行；受阻时外部请求进入等待，用户请求被忽略。
        private func admit(
            _ route: Route,
            _ source: LYRouteSource,
            placement: LYRoutePlacement,
            proposed: LYOpenResult,
            handle: @escaping (LYRouteContext<Route>) -> Void
        ) -> Submission {
            guard canNavigate(to: placement) else { return deferOrIgnore(route, source, placement: placement) }
            // 新准入的外部请求取代所有更早的等待请求。
            var intent: Pending?
            if source.isExternal {
                pending = nil
                sequence &+= 1
                intent = Pending(route: route, source: source, sequence: sequence, sessionID: host?.routerSessionID)
            }
            for observer in observers {
                observer.routeWillOpen(route.kind, source: source)
            }
            return execute(kind: route.kind, source: source, intent: intent, proposed: proposed) { [self] in
                dispatch(route, source, placement: placement, handle: handle)
            }
        }

        /// 用户请求受阻时忽略；外部请求保存为最近的等待项。
        private func deferOrIgnore(_ route: Route, _ source: LYRouteSource, placement: LYRoutePlacement) -> Submission {
            guard source.isExternal else { return settled(route.kind, source, .ignored) }
            sequence &+= 1
            pending = Pending(route: route, source: source, sequence: sequence, sessionID: host?.routerSessionID)
            observeBlockingPresentation(for: placement)
            return settled(route.kind, source, .deferred)
        }

        /// 进入目标域并调用处理器。切换目标域属于展示阶段，之后不再被返回抢占。
        private func dispatch(
            _ route: Route,
            _ source: LYRouteSource,
            placement: LYRoutePlacement,
            handle: (LYRouteContext<Route>) -> Void
        ) {
            if placement != .current {
                currentExecution?.phase = .presenting
                guard host?.select(placement) != nil else {
                    markResult(.failed(.unavailable))
                    return
                }
            }
            handle(LYRouteContext(router: self, route: route, source: source))
        }

        /// 在已取得执行权的处理器内继续导航到另一路由，不重新准入、不创建新的执行。
        func continueNavigation(to route: Route, source: LYRouteSource) {
            guard let execution = currentExecution, isCurrent(execution) else { return }
            guard let entry = registry.entries[route.kind] else {
                if allowsUnregistered, let fallback {
                    fallback.handle(route, .unregistered, LYRouteContext(router: self, route: route, source: source))
                } else {
                    markResult(.failed(.unregistered))
                }
                return
            }
            guard entry.policy.status != .disabled, !rewrite.isDisabled(route.kind) else {
                markResult(.failed(.unavailable))
                return
            }
            guard entry.policy.validate(route) else {
                markResult(.failed(.invalidParameter))
                return
            }
            dispatch(route, source, placement: .current, handle: { entry.handle(route, $0) })
        }

        /// 处理器内取得新的执行权执行一段操作，例如确认框确认后的后续导航。
        @discardableResult
        func performUserNavigation(
            route: Route,
            source: LYRouteSource,
            _ operation: @escaping (LYRouteContext<Route>) -> Void
        ) -> LYOpenResult {
            guard !stopped else { return .failed(.stopped) }
            guard canNavigate else { return .ignored }
            return execute(kind: route.kind, source: source, intent: nil, proposed: .failed(.unavailable)) { [self] in
                operation(LYRouteContext(router: self, route: route, source: source))
            }.immediate
        }

        // MARK: - Admission

        /// 宿主与当前导航域是否允许导航；与“是否已有执行”无关，因此合法的返回可以抢占准备阶段。
        var isNavigationContextReady: Bool {
            guard !stopped, let host, host.isRouterReady,
                  host.routerRootViewController?.presentedViewController == nil,
                  host.routerRootViewController?.transitionCoordinator == nil else { return false }
            return host.navigationDomain(for: .current).allSatisfy(Self.isIdle)
        }

        var canNavigate: Bool {
            currentExecution == nil && isNavigationContextReady
        }

        func canNavigate(to placement: LYRoutePlacement) -> Bool {
            canNavigate && targetDomain(for: placement).allSatisfy(Self.isIdle)
        }

        func targetDomain(for placement: LYRoutePlacement) -> [UINavigationController] {
            guard placement != .current, let host else { return [] }
            return host.navigationDomain(for: placement)
        }

        var currentDomain: [UINavigationController] {
            host?.navigationDomain(for: .current) ?? []
        }

        static func isIdle(_ navigation: UINavigationController) -> Bool {
            navigation.transitionCoordinator == nil && navigation.presentedViewController == nil
                && navigation.topViewController?.presentedViewController == nil
        }

        // MARK: - Pending

        /// 宿主状态变化后尝试执行等待中的外部请求。
        func schedulePending() {
            guard let pending else { return }
            guard canNavigate(to: placement(of: pending.route)) else {
                observeBlockingPresentation(for: placement(of: pending.route))
                return
            }
            Task { [weak self] in self?.consumePending() }
        }

        /// 只由导航事件投递一次；旧执行已终止后，也能在 UIKit 清除 coordinator 后消费最新请求。
        func drainPendingAfterNavigationEvent() {
            guard pending != nil else { return }
            let epoch = generation
            Task { [weak self] in
                guard let self, isCurrent(epoch) else { return }
                consumePending()
            }
        }

        /// 先取走等待项再执行；临时再次受阻时会重新进入等待，执行期间到达的新请求不会被覆盖。
        private func consumePending() {
            guard let intent = pending else { return }
            guard canNavigate(to: placement(of: intent.route)) else {
                observeBlockingPresentation(for: placement(of: intent.route))
                return
            }
            pending = nil
            let session = host?.routerSessionID
            guard intent.sessionID == nil || intent.sessionID == session else { return }
            _ = submit(intent.route, source: intent.source)
        }

        func placement(of route: Route) -> LYRoutePlacement {
            registry.entries[route.kind]?.policy.placement ?? .current
        }

        // MARK: - Observers

        func settled(_ kind: Route.Kind?, _ source: LYRouteSource, _ result: LYOpenResult) -> Submission {
            notifySettle(kind, source: source, result: result)
            return Submission(immediate: result)
        }

        func notifySettle(_ kind: Route.Kind?, source: LYRouteSource, result: LYOpenResult) {
            for observer in observers {
                observer.routeDidSettle(kind, source: source, result: result)
            }
        }
    }
#endif
