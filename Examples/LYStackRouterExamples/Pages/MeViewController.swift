import DemoRoutes
import UIKit

/// 我的 Tab 的根页面：组装方式、登录状态、降级开关与等待中的深链演示。
final class MeViewController: DemoPage {
    // MARK: - Properties

    var signOut: () -> Void = {}
    var setDegraded: (Bool) -> Void = { _ in }
    var presentSheetThenDeepLink: () -> Void = {}
    var deliverDeepLinkLater: () -> Void = {}

    private let assembly: String
    private let sessionLabel = UILabel()
    private var degraded = false

    // MARK: - Initialization

    init(metrics: DemoMetrics, assembly: String) {
        self.assembly = assembly
        super.init(pageID: "me", title: "我的", identity: nil, metrics: metrics)
    }

    // MARK: - View Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        addNote(assembly, id: "me.assembly")
        addNote("未登录", id: "me.session")
        addButton("钱包（需要登录）", id: "me.wallet") { [weak self] in self?.open(.wallet) }
        addButton("退出登录", id: "me.signOut") { [weak self] in self?.signOut() }
        addButton("成员 m1", id: "open.member.m1") { [weak self] in self?.open(.member("m1")) }
        addButton("降级成员页：关", id: "me.degrade") { [weak self] in self?.toggleDegraded() }
        addButton("弹出面板，1 秒后收到深链", id: "me.sheetDeepLink") { [weak self] in self?.presentSheetThenDeepLink() }
        addNote("点下面的按钮后切到首页、按住返回手势不放：转场期间到达的深链会等待，手势取消后再打开。")
        addButton("6 秒后收到深链 lydemo://club/77", id: "me.delayedDeepLink") { [weak self] in
            self?.deliverDeepLinkLater()
        }
    }

    // MARK: - Internal

    func showSession(_ signedIn: Bool) {
        loadViewIfNeeded()
        label(id: "me.session")?.text = signedIn ? "已登录" : "未登录"
    }

    // MARK: - Private

    private func toggleDegraded() {
        degraded.toggle()
        setDegraded(degraded)
        button(id: "me.degrade")?.configuration?.title = degraded ? "降级成员页：开" : "降级成员页：关"
    }

    private func label(id: String) -> UILabel? {
        view.firstSubview(identifier: id) as? UILabel
    }

    private func button(id: String) -> UIButton? {
        view.firstSubview(identifier: id) as? UIButton
    }
}

/// 演示弹窗：外部请求在它关闭前进入等待。
final class SheetPage: DemoPage {
    init(metrics: DemoMetrics) {
        super.init(pageID: "sheet", title: "面板", identity: nil, metrics: metrics)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addNote("1 秒后收到 lydemo://club/99。面板关闭前请求处于等待，关闭后自动打开。")
        addButton("关闭", id: "sheet.close") { [weak self] in self?.dismiss(animated: true) }
    }
}

private extension UIView {
    func firstSubview(identifier: String) -> UIView? {
        if accessibilityIdentifier == identifier { return self }
        for subview in subviews {
            if let match = subview.firstSubview(identifier: identifier) { return match }
        }
        return nil
    }
}
