import LYStackRouter
import UIKit

/// 有明确出现状态与移出计数的普通 UIKit 页面。
@MainActor
final class CompatibilityPage: UIViewController, LYPageIdentifiable, LYRoutePageLifecycle {
    let identity: Int?
    var onFirstAppearance: (() -> Void)?
    private(set) var appeared = false
    private(set) var removedCount = 0
    private let resultLabel = UILabel()

    var routeIdentity: AnyHashable? {
        identity
    }

    init(identity: Int?) {
        self.identity = identity
        super.init(nibName: nil, bundle: nil)
        title = identity.map { "Detail \($0)" } ?? "Compatibility"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        resultLabel.numberOfLines = 0
        resultLabel.text = "Checking public routing APIs…"
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(resultLabel)
        NSLayoutConstraint.activate([
            resultLabel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 20),
            resultLabel.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -20),
            resultLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        appeared = true
        let ready = onFirstAppearance
        onFirstAppearance = nil
        ready?()
    }

    func routerDidRemovePage() {
        removedCount += 1
    }

    func showReport(passed: Bool, count: Int) {
        resultLabel.text = "\(passed ? "PASS" : "FAIL") · \(count) public API checks\n\nSee Documents/compatibility-report.json"
    }
}
