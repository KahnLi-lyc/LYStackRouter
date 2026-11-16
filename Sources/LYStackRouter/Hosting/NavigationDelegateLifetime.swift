#if canImport(UIKit)
    import os
    import UIKit

    /// 只在绑定业务代理时订阅其释放；不持有业务代理或它的关联对象。
    @MainActor
    final class NavigationDelegateLifetime {
        private weak var bag: DelegateLifetimeBag?
        private let identity = UUID()
        private var isActive = true

        init(delegate: any UINavigationControllerDelegate, onRelease: @escaping @MainActor @Sendable () -> Void) {
            let bag = DelegateLifetimeBag.associated(with: delegate)
            self.bag = bag
            bag.subscribe(identity) { [weak self] in
                guard let self, isActive else { return }
                isActive = false
                onRelease()
            }
        }

        /// 替换代理时同步取消旧订阅；已投递的旧通知也不能影响新代理。
        func stop() {
            isActive = false
            bag?.unsubscribe(identity)
            bag = nil
        }

        deinit {
            bag?.unsubscribe(identity)
        }
    }

    /// 一个业务代理可以同时服务多个宿主，关联对象保存各自独立的弱订阅。
    private final class DelegateLifetimeBag: NSObject, Sendable {
        typealias Notification = @MainActor @Sendable () -> Void

        @MainActor private static var associationKey: UInt8 = 0
        private let notifications = OSAllocatedUnfairLock(initialState: [UUID: Notification]())

        @MainActor
        static func associated(with delegate: any UINavigationControllerDelegate) -> DelegateLifetimeBag {
            if let bag = objc_getAssociatedObject(delegate, &associationKey) as? DelegateLifetimeBag { return bag }
            let bag = DelegateLifetimeBag()
            objc_setAssociatedObject(delegate, &associationKey, bag, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return bag
        }

        func subscribe(_ identity: UUID, notification: @escaping Notification) {
            notifications.withLock { $0[identity] = notification }
        }

        func unsubscribe(_ identity: UUID) {
            _ = notifications.withLock { $0.removeValue(forKey: identity) }
        }

        deinit {
            // 代理可在任意线程释放；这里只取 Sendable 快照，UIKit 更新投递到下一次 MainActor 执行。
            let pending = notifications.withLock { Array($0.values) }
            Task { @MainActor in pending.forEach { $0() } }
        }
    }
#endif
