#if canImport(UIKit)
    import UIKit

    /// 一次导航的执行权与独立结算。底层任务是否响应取消，不影响等待者拿到结果。
    @MainActor
    final class NavigationExecution {
        // MARK: - Properties

        /// 执行阶段：准备中可被返回抢占；展示中不可抢占。
        enum Phase {
            case preparing, presenting
        }

        let sessionID: String?
        let generation: UUID
        private(set) weak var source: UIViewController?
        private(set) weak var navigation: UINavigationController?
        private(set) var hasOrigin = false
        var phase: Phase = .preparing
        var proposedResult: LYOpenResult = .failed(.unavailable)
        private(set) var result: LYOpenResult?
        /// 异步准备任务，例如 `prepare` 中的网络请求。
        var preparationTask: Task<Void, Never>?
        /// 等待转场完成后结算的任务。
        var completionTask: Task<Void, Never>?
        /// 转场完成观察最多登记一次；仅保存身份值，不持有 UIKit 协调器。
        var observedTransitionID: ObjectIdentifier?
        /// 结算时通知观察者。
        var onFinish: ((LYOpenResult) -> Void)?
        private var waiters: [CheckedContinuation<LYOpenResult, Never>] = []
        /// 只保留本次执行实际等过的弱转场凭据，不延长 UIKit 对象生命周期。
        private var completedTransitions: [CompletedTransition] = []

        // MARK: - Initialization

        init(sessionID: String?, generation: UUID) {
            self.sessionID = sessionID
            self.generation = generation
        }

        // MARK: - Origin

        /// 在首次挂起前绑定真实来源页面；不延长页面与导航栈生命周期。
        func bind(source: UIViewController, navigation: UINavigationController) {
            self.source = source
            self.navigation = navigation
            hasOrigin = true
            phase = .preparing
        }

        /// 仅在真实 UIKit 完成回调结束等待后记录。
        func rememberCompletedTransition(_ transition: any UIViewControllerTransitionCoordinator) {
            guard result == nil else { return }
            completedTransitions.removeAll { $0.transition == nil }
            if !hasCompletedTransition(transition) {
                completedTransitions.append(CompletedTransition(transition))
            }
        }

        /// nil 表示没有转场；非 nil 必须是本次执行实际等过、且仍为同一对象的转场。
        func hasCompletedTransition(_ transition: (any UIViewControllerTransitionCoordinator)?) -> Bool {
            guard let transition else { return true }
            guard result == nil else { return false }
            return completedTransitions.contains { $0.transition === transition }
        }

        // MARK: - Settlement

        /// 多个调用者以及结算后才到达的调用者读取同一结果。
        func value() async -> LYOpenResult {
            if let result { return result }
            return await withCheckedContinuation { waiters.append($0) }
        }

        /// 先发布不可变结果，再唤醒全部等待者；迟到的完成不能覆盖第一次结算。
        func finish(_ result: LYOpenResult) {
            guard self.result == nil else { return }
            self.result = result
            completedTransitions.removeAll()
            let pending = waiters
            waiters.removeAll()
            pending.forEach { $0.resume(returning: result) }
            let notify = onFinish
            onFinish = nil
            notify?(result)
        }

        /// 抢占者同步取走旧任务句柄，随后可以先结算再取消底层任务。
        func takeWorkers() -> [Task<Void, Never>] {
            let workers = [preparationTask, completionTask].compactMap(\.self)
            preparationTask = nil
            completionTask = nil
            return workers
        }
    }

    /// 只观察实际 UIKit 对象；地址被复用也不会把旧完成结果授予新转场。
    @MainActor
    private final class CompletedTransition {
        weak var transition: (any UIViewControllerTransitionCoordinator)?

        init(_ transition: any UIViewControllerTransitionCoordinator) {
            self.transition = transition
        }
    }
#endif
