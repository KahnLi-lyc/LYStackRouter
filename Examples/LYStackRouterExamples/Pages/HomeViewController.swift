import DemoRoutes
import UIKit

/// 首页 Tab 的根页面：打开俱乐部与 URL 入口。
final class HomeViewController: DemoPage {
    /// 以深链来源打开 URL。
    var openURL: (URL) -> Void = { _ in }

    init(metrics: DemoMetrics) {
        super.init(pageID: "home", title: "首页", identity: nil, metrics: metrics)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        addButton("俱乐部 A", id: "home.club.A") { [weak self] in self?.open(.club("A")) }
        addButton("俱乐部 B", id: "home.club.B") { [weak self] in self?.open(.club("B")) }
        addButton("链接 lydemo://club/42", id: "home.url.club") { [weak self] in
            if let url = URL(string: "lydemo://club/42") { self?.openURL(url) }
        }
        addButton("链接 https://demo.example.com/chat/c2", id: "home.url.chat") { [weak self] in
            if let url = URL(string: "https://demo.example.com/chat/c2") { self?.openURL(url) }
        }
    }
}
