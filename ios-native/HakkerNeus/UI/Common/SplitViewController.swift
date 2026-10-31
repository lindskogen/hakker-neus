import UIKit

/// The root screen. Narrow windows show one stack (`primary`), as on the iPhone. Wide windows
/// (iPads in landscape, and large iPads in portrait) keep the lists in a column on the left and
/// open articles, comments and user pages in a second stack (`detail`) beside them.
///
/// When the window changes between the two (rotation, Split View, Stage Manager), the screens
/// above the lists move across, so nothing that was open is lost.
final class SplitViewController: UIViewController {
    let primary: NavigationController
    let detail = NavigationController()
    /// Screens that stay in the primary stack (the lists); the rest go to the side column.
    var isList: (UIViewController) -> Bool = { _ in true }

    /// From this width on, articles and comments open beside the list.
    static let minimumSplitWidth: CGFloat = 1000

    private(set) var isSplit = false
    private let placeholder = DetailPlaceholderViewController()
    private let divider = UIView()

    init(primary: NavigationController) {
        self.primary = primary
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark
        for child in [primary, detail] {
            addChild(child)
            view.addSubview(child.view)
            child.didMove(toParent: self)
        }
        // The placeholder stays at the bottom of the side column: going back past the first
        // screen there empties the column.
        detail.setViewControllers([placeholder], animated: false)
        detail.view.isHidden = true
        divider.backgroundColor = UIColor(white: 1, alpha: 0.12)
        view.addSubview(divider)
    }

    override var childForStatusBarStyle: UIViewController? { primary }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let bounds = view.bounds
        let split = bounds.width >= Self.minimumSplitWidth
        if split != isSplit {
            isSplit = split
            moveScreens()
        }
        detail.view.isHidden = !split
        divider.isHidden = !split
        guard split else {
            primary.view.frame = bounds
            return
        }
        let listWidth = (bounds.width * 0.38).clamped(to: 380...480).rounded()
        let hairline = 1 / max(traitCollection.displayScale, 1)
        primary.view.frame = CGRect(x: 0, y: 0, width: listWidth, height: bounds.height)
        divider.frame = CGRect(x: listWidth, y: 0, width: hairline, height: bounds.height)
        detail.view.frame = CGRect(x: listWidth + hairline, y: 0, width: bounds.width - listWidth - hairline, height: bounds.height)
    }

    /// Shows `viewController` in the side column: replacing what's there (opened from a list),
    /// or on top of it (opened from something already in the column).
    func showDetail(_ viewController: UIViewController, replacing: Bool) {
        guard replacing else {
            detail.pushViewController(viewController, animated: true)
            return
        }
        detail.setViewControllers([placeholder, viewController], animated: false)
        if !UIAccessibility.isReduceMotionEnabled {
            let fade = CATransition()
            fade.duration = 0.2
            fade.type = .fade
            detail.view.layer.add(fade, forKey: "replace")
        }
    }

    /// Moves the screens above the lists into the side column, or back on top of the lists.
    private func moveScreens() {
        if isSplit {
            let stack = primary.viewControllers
            let lists = stack.lastIndex(where: isList).map { stack[...$0] } ?? []
            let moved = stack.dropFirst(lists.count)
            guard !moved.isEmpty else { return }
            primary.setViewControllers(Array(lists), animated: false)
            detail.setViewControllers([placeholder] + moved, animated: false)
        } else {
            let moved = detail.viewControllers.dropFirst()
            guard !moved.isEmpty else { return }
            // Out of one stack before into the other.
            detail.setViewControllers([placeholder], animated: false)
            primary.setViewControllers(primary.viewControllers + moved, animated: false)
        }
    }

    /// Every screen in both stacks, lists first.
    var allViewControllers: [UIViewController] {
        primary.viewControllers + detail.viewControllers.dropFirst()
    }
}

/// The empty side column, before anything is opened.
private final class DetailPlaceholderViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark
        let label = UILabel()
        label.text = "Pick a story"
        label.font = Theme.Font.light(size: 24)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor(white: 1, alpha: 0.25)
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
        ])
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
