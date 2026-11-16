import LYStackRouter
import UIKit

/// 验证宿主只通过公开接口消费路由库。
enum CompatibilityRoute: LYRoutable {
    case detail(Int), modal, preparation, action

    enum Kind: CaseIterable, Sendable {
        case detail, modal, preparation, action
    }

    var kind: Kind {
        switch self {
        case .detail: .detail
        case .modal: .modal
        case .preparation: .preparation
        case .action: .action
        }
    }
}

/// 准备任务故意不响应取消，验证调用方仍能及时释放执行权。
@MainActor
final class CompatibilityGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var waiting = false

    func wait() async {
        waiting = true
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}

/// 两种产品消费方式共享同一份路由行为。
struct CompatibilityModule: LYRouteModule {
    static let moduleID = "compatibility"
    private let gate: CompatibilityGate

    init(environment: LYRouteEnvironment) throws {
        gate = try environment.require(CompatibilityGate.self)
    }

    func register(into builder: inout LYStackRouteRegistry<CompatibilityRoute>.Builder) {
        builder.page(.detail) { route, context in
            guard case let .detail(id) = route else { return }
            context.show(identity: id) { CompatibilityPage(identity: id) }
        }
        builder.action(.modal) { _, context in
            context.present(UINavigationController(rootViewController: CompatibilityPage(identity: nil)), animated: false)
        }
        let gate = gate
        builder.action(.preparation) { _, context in
            context.prepare { context in
                await gate.wait()
                guard await context.isStillValid() else { return }
                context.markPerformed()
            }
        }
        builder.action(.action) { _, context in context.markPerformed() }
    }
}
