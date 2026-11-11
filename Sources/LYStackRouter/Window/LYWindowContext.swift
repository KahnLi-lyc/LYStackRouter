#if canImport(UIKit)
    import UIKit

    /// 场景感知的窗口、控制器与几何查询。所有 UIKit 查询都在主执行器进行。
    ///
    /// 多窗口应用优先传入来源视图、窗口或场景；自动查询只接受唯一的前台活跃场景。
    /// 顶层控制器可用于 Alert、Toast 等展示辅助，业务导航应交给路由器。
    @MainActor
    public enum LYWindowContext {
        // MARK: - Public

        /// 返回唯一的前台活跃窗口场景；没有或存在多个候选时返回 nil。
        public static func activeWindowScene() -> UIWindowScene? {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
                .filter { $0.activationState == .foregroundActive }
            return scenes.count == 1 ? scenes.first : nil
        }

        /// 返回视图实际所属的窗口场景；尚未挂入窗口时返回 nil。
        public static func windowScene(for view: UIView) -> UIWindowScene? {
            view.window?.windowScene
        }

        /// 返回指定场景的真实 key window，包含可能成为 key 的浮层窗口。
        public static func keyWindow(in scene: UIWindowScene) -> UIWindow? {
            scene.windows.first { $0.isKeyWindow }
        }

        /// 返回指定场景中可见且有根控制器的 normal 窗口。
        ///
        /// 优先选择 normal key window；其余候选必须唯一，存在歧义时返回 nil。
        public static func mainWindow(in scene: UIWindowScene) -> UIWindow? {
            resolvedMainWindow(in: scene.windows)
        }

        /// 从指定控制器展开模态、导航、Tab 与已显示的搜索结果，返回顶层控制器。
        ///
        /// 空容器和未知的自定义容器返回容器本身；不会加载尚未展示的搜索结果视图。
        public static func topViewController(from controller: UIViewController?) -> UIViewController? {
            guard var current = controller else { return nil }
            var visited = Set<ObjectIdentifier>()
            visited.insert(ObjectIdentifier(current))
            while let next = nextController(from: current), visited.insert(ObjectIdentifier(next)).inserted {
                current = next
            }
            return current
        }

        /// 从指定窗口的根控制器查询顶层控制器。
        public static func topViewController(in window: UIWindow) -> UIViewController? {
            topViewController(from: window.rootViewController)
        }

        /// 从指定场景的主窗口查询顶层控制器；无法唯一确定主窗口时返回 nil。
        public static func topViewController(in scene: UIWindowScene) -> UIViewController? {
            topViewController(from: mainWindow(in: scene)?.rootViewController)
        }

        /// 返回窗口的有效几何尺寸，必要时回退到窗口所属场景及其屏幕。
        public static func windowBounds(for window: UIWindow) -> CGRect {
            let scene = window.windowScene
            return resolvedBounds(window: window.bounds, scene: scene.map { sceneBounds(in: $0) }, screen: scene?.screen.bounds)
        }

        /// 返回主窗口、场景或场景所属屏幕的第一个有效矩形；均无效时返回零。
        public static func windowBounds(in scene: UIWindowScene) -> CGRect {
            resolvedBounds(window: mainWindow(in: scene)?.bounds, scene: sceneBounds(in: scene), screen: scene.screen.bounds)
        }

        /// 优先返回视图本身的有效 bounds，再回退到其实际窗口；未挂载且无有效 bounds 时返回零。
        public static func containerBounds(for view: UIView) -> CGRect {
            if isValidBounds(view.bounds) { return view.bounds }
            return view.window.map { windowBounds(for: $0) } ?? .zero
        }

        /// 返回指定窗口当前的安全区。布局尚未完成时值可能为零。
        public static func safeAreaInsets(for window: UIWindow) -> UIEdgeInsets {
            window.safeAreaInsets
        }

        /// 返回指定场景主窗口当前的安全区；无法确定主窗口时返回零。
        public static func safeAreaInsets(in scene: UIWindowScene) -> UIEdgeInsets {
            mainWindow(in: scene)?.safeAreaInsets ?? .zero
        }

        // MARK: - Internal

        /// 按窗口、场景、屏幕顺序选择有效矩形，不依赖 UIKit 状态。
        nonisolated static func resolvedBounds(window: CGRect?, scene: CGRect?, screen: CGRect?) -> CGRect {
            [window, scene, screen].compactMap(\.self).first(where: isValidBounds) ?? .zero
        }

        /// normal 窗口候选必须可见且拥有根控制器；不依赖场景枚举的顺序。
        static func resolvedMainWindow(in windows: [UIWindow]) -> UIWindow? {
            let candidates = windows.filter {
                $0.windowLevel == .normal && !$0.isHidden && $0.alpha > 0 && $0.rootViewController != nil
            }
            let keys = candidates.filter(\.isKeyWindow)
            if keys.count == 1 { return keys.first }
            return candidates.count == 1 ? candidates.first : nil
        }

        // MARK: - Private

        private static func sceneBounds(in scene: UIWindowScene) -> CGRect {
            #if compiler(>=6.2)
                if #available(iOS 26.0, *) { return scene.effectiveGeometry.coordinateSpace.bounds }
            #endif
            return scene.coordinateSpace.bounds
        }

        private static func nextController(from controller: UIViewController) -> UIViewController? {
            if let presented = controller.presentedViewController { return presented }
            if let navigation = controller as? UINavigationController { return navigation.visibleViewController }
            if let tabs = controller as? UITabBarController { return tabs.selectedViewController }
            if let search = controller as? UISearchController, search.isActive,
               let results = search.searchResultsController, results.viewIfLoaded?.window != nil {
                return results
            }
            return nil
        }

        private nonisolated static func isValidBounds(_ bounds: CGRect) -> Bool {
            !bounds.isNull && !bounds.isInfinite && bounds.origin.x.isFinite && bounds.origin.y.isFinite
                && bounds.width.isFinite && bounds.height.isFinite && bounds.width > 0 && bounds.height > 0
        }
    }
#endif
