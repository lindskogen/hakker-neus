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

    /// Posted with a story ID when that story starts or stops being the one in the side column.
    static let activeStoryDidChange = Notification.Name("SplitViewController.activeStoryDidChange")

    /// The story open in the side column, which the lists mark.
    private(set) var activeStoryID: Int? {
        didSet {
            guard activeStoryID != oldValue else { return }
            for id in [oldValue, activeStoryID].compactMap({ $0 }) {
                NotificationCenter.default.post(name: Self.activeStoryDidChange, object: id)
            }
        }
    }
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
        detail.onDidShow = { [unowned self] _ in updateActiveStory() }
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
        updateActiveStory()
    }

    /// The story of the first screen in the side column: what was opened from the list.
    private func updateActiveStory() {
        let opened = isSplit ? detail.viewControllers.dropFirst().first : nil
        activeStoryID = (opened as? ArticleViewController)?.story?.id ?? (opened as? CommentsViewController)?.transitionStoryID
    }

    /// Moves the screens above the lists into the side column, or back on top of the lists.
    private func moveScreens() {
        defer { updateActiveStory() }
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

/// The empty side column: a zen quote, a new one each time the column empties.
private final class DetailPlaceholderViewController: UIViewController {
    private static let quotes: [(text: String, source: String)] = [
        ("Before enlightenment, chop wood, carry water. After enlightenment, chop wood, carry water.", "Zen proverb"),
        ("When walking, walk. When eating, eat.", "Zen proverb"),
        ("Sitting quietly, doing nothing, spring comes, and the grass grows by itself.", "Zenrin Kushū"),
        ("Let go, or be dragged.", "Zen proverb"),
        ("No snowflake ever falls in the wrong place.", "Zen proverb"),
        ("If you cannot find the truth right where you are, where else do you expect to find it?", "Dōgen"),
        ("In the beginner’s mind there are many possibilities, but in the expert’s there are few.", "Shunryū Suzuki"),
        ("The obstacle is the path.", "Zen proverb"),
        ("Do not seek the truth; only cease to cherish opinions.", "Sengcan"),
        ("Empty your mind, be formless, shapeless, like water.", "Bruce Lee"),
    ]

    private let quoteLabel = UILabel()
    private let sourceLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark
        quoteLabel.font = Theme.Font.light(size: 26)
        quoteLabel.textColor = UIColor(white: 1, alpha: 0.35)
        quoteLabel.numberOfLines = 0
        quoteLabel.textAlignment = .center
        sourceLabel.font = Theme.Font.body(size: 15, style: .subheadline)
        sourceLabel.textColor = UIColor(white: 1, alpha: 0.2)
        sourceLabel.textAlignment = .center
        for label in [quoteLabel, sourceLabel] { label.adjustsFontForContentSizeCategory = true }

        let stack = UIStackView(arrangedSubviews: [quoteLabel, sourceLabel])
        stack.axis = .vertical
        stack.spacing = Theme.padding * 1.5
        stack.isAccessibilityElement = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Theme.padding * 4),
        ])
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let quote = Self.quotes.randomElement()!
        quoteLabel.text = quote.text
        sourceLabel.text = "— " + quote.source
        quoteLabel.superview?.accessibilityLabel = "\(quote.text) — \(quote.source)"
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
