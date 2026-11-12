import UIKit

/// Screens that show the navigation bar (with its back button), which is hidden for the rest.
@MainActor
protocol ShowsNavigationBar {}

/// Screens where swiping right in the content area does something else (like saving a story row),
/// so only the edge swipe goes back.
@MainActor
protocol EdgeOnlySwipeBack {}

/// The places the sidebar switches between. They're alone in the stack, the sidebar opens over
/// them with a swipe from the left edge, and the corner button scrolls them to the top.
@MainActor
protocol TopLevelScreen {
    /// The list, whose scrolling shows the corner button; nil before it's loaded.
    var scrollView: UIScrollView? { get }
}

extension TopLevelScreen {
    func scrollToTop() {
        guard let scrollView else { return }
        scrollView.setContentOffset(CGPoint(x: 0, y: -scrollView.adjustedContentInset.top), animated: true)
    }
}

/// Navigation controller with a hidden bar that keeps the interactive swipe-back gestures,
/// and adds the sidebar from the left edge on top-level places, and a swipe forward from the
/// right edge that, like a browser's forward button, brings back what was last left with back.
///
/// UIKit disables both pop gestures while the bar is hidden. Taking over their delegates
/// re-enables them: the edge swipe everywhere, and on iOS 26 also the swipe from anywhere in
/// the content area. iOS 18–25 only get the edge swipe.
final class NavigationController: UINavigationController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    private let forwardSwipe = UIScreenEdgePanGestureRecognizer()
    private var interactivePush: UIPercentDrivenInteractiveTransition?

    /// Screens left with back, the next one to bring back last. The same screens come back, so
    /// they're as they were left, scrolled where they were.
    private var forwardStack: [UIViewController] = []
    /// The screen being brought back by the swipe forward, until it's in place.
    private var forwardPushing: UIViewController?
    /// The browser last presented (Safari), brought back by the swipe forward once there's
    /// nothing else to go forward to.
    private var forwardBrowser: UIViewController?
    /// The stack as it was last shown, to tell going back from opening something.
    private var shownStack: [UIViewController] = []

    /// The lower-right button (lower-left if set for left hands), above every screen so it stays
    /// put while they change underneath: on a top-level place scrolled down more than half a
    /// screen, scrolls it back to the top.
    private let cornerButton = UIButton(type: .system)
    private var cornerButtonLeading: NSLayoutConstraint!
    private var cornerButtonTrailing: NSLayoutConstraint!
    private var cornerButtonShown = false
    private var scrollObservation: NSKeyValueObservation?
    private weak var observedScrollView: UIScrollView?
    /// The stacked button above the corner button, or in its place while it's hidden.
    private var stackedAboveCorner: NSLayoutConstraint!
    private var stackedInCorner: NSLayoutConstraint!

    /// Puts the corner button in the lower-left corner instead of the lower-right.
    var cornerButtonOnLeft = false {
        didSet { placeCornerButton() }
    }

    /// The sidebar's places, built as it opens. Nil for no sidebar.
    var sidebarSections: (() -> [SidebarSection])?
    /// The colour of the line down the sidebar's edge.
    var sidebarAccent: (() -> UIColor)?
    private var sidebar: SidebarView?
    private let sidebarEdgeSwipe = UIScreenEdgePanGestureRecognizer()
    private let sidebarCloseSwipe = UIPanGestureRecognizer()

    /// A smaller button stacked above the corner button, for something to do to the screen
    /// showing (on a feed, hiding read stories); nil for none.
    var stackedButton: ((UIViewController) -> StackedButton?)?
    private let stackedButtonView = UIButton(type: .system)
    private var stackedButtonAction: (() -> Void)?

    struct StackedButton {
        let systemImage: String
        let accessibilityLabel: String
        let action: () -> Void
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        navigationBar.overrideUserInterfaceStyle = .dark
        navigationBar.tintColor = .white
        view.backgroundColor = Theme.Color.backgroundDark
        delegate = self

        interactivePopGestureRecognizer?.delegate = self
        if #available(iOS 26, *) {
            // Apple documents this recognizer as "only for failure requirements", so this may need
            // revisiting in future iOS versions. Covered by NavigationUITests.
            interactiveContentPopGestureRecognizer?.delegate = self
        }

        configureCornerButton()

        sidebarEdgeSwipe.edges = .left
        sidebarEdgeSwipe.delegate = self
        sidebarEdgeSwipe.addTarget(self, action: #selector(handleSidebarSwipe(_:)))
        view.addGestureRecognizer(sidebarEdgeSwipe)
        sidebarCloseSwipe.delegate = self
        sidebarCloseSwipe.addTarget(self, action: #selector(handleSidebarSwipe(_:)))
        view.addGestureRecognizer(sidebarCloseSwipe)

        forwardSwipe.edges = .right
        forwardSwipe.delegate = self
        forwardSwipe.addTarget(self, action: #selector(handleForwardSwipe(_:)))
        view.addGestureRecognizer(forwardSwipe)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: Corner button

    /// Glass on iOS 26, a dark disc before.
    private static func floatingButtonConfiguration(pointSize: CGFloat) -> UIButton.Configuration {
        var config: UIButton.Configuration
        if #available(iOS 26, *) {
            config = .glass()
        } else {
            config = .filled()
            config.baseBackgroundColor = UIColor(white: 0.25, alpha: 0.9)
        }
        config.preferredSymbolConfigurationForImage = .init(pointSize: pointSize, weight: .semibold)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        return config
    }

    private func configureCornerButton() {
        cornerButton.configuration = Self.floatingButtonConfiguration(pointSize: 18)
        cornerButton.configuration?.image = UIImage(systemName: "arrow.up")
        cornerButton.accessibilityIdentifier = "cornerButton"
        cornerButton.accessibilityLabel = "Scroll to Top"
        cornerButton.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Open Sidebar") { [unowned self] _ in
                openSidebar(animated: true)
                return sidebar != nil
            },
        ]
        cornerButton.alpha = 0
        cornerButton.addAction(UIAction { [unowned self] _ in
            (topViewController as? TopLevelScreen)?.scrollToTop()
        }, for: .touchUpInside)

        cornerButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cornerButton)
        NSLayoutConstraint.activate([
            cornerButton.widthAnchor.constraint(equalToConstant: 52),
            cornerButton.heightAnchor.constraint(equalToConstant: 52),
            cornerButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.padding),
        ])
        cornerButtonLeading = cornerButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Theme.padding * 2)
        cornerButtonTrailing = cornerButton.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Theme.padding * 2)
        placeCornerButton()

        stackedButtonView.configuration = Self.floatingButtonConfiguration(pointSize: 15)
        stackedButtonView.accessibilityIdentifier = "stackedButton"
        stackedButtonView.alpha = 0
        stackedButtonView.addAction(UIAction { [unowned self] _ in
            stackedButtonAction?()
        }, for: .touchUpInside)
        stackedButtonView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stackedButtonView)
        NSLayoutConstraint.activate([
            stackedButtonView.widthAnchor.constraint(equalToConstant: 42),
            stackedButtonView.heightAnchor.constraint(equalToConstant: 42),
            stackedButtonView.centerXAnchor.constraint(equalTo: cornerButton.centerXAnchor),
        ])
        stackedAboveCorner = stackedButtonView.bottomAnchor.constraint(equalTo: cornerButton.topAnchor, constant: -Theme.padding * 1.5)
        stackedInCorner = stackedButtonView.centerYAnchor.constraint(equalTo: cornerButton.centerYAnchor)
        stackedInCorner.isActive = true

        NotificationCenter.default.addObserver(forName: UIAccessibility.voiceOverStatusDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateCornerButton(for: self?.topViewController, animated: true) }
        }
    }

    private func placeCornerButton() {
        guard isViewLoaded else { return }
        cornerButtonLeading.isActive = cornerButtonOnLeft
        cornerButtonTrailing.isActive = !cornerButtonOnLeft
    }

    /// Shows the corner button as it should be for `viewController`, and follows its scrolling.
    func updateCornerButton(for viewController: UIViewController?, animated: Bool) {
        observeScrolling(of: (viewController as? TopLevelScreen)?.scrollView)
        view.bringSubviewToFront(cornerButton)
        setCornerButtonShown(showsCornerButton(on: viewController), animated: animated)
        updateStackedButton(for: viewController, animated: animated)
        keepSidebarBehind()
    }

    /// On a top-level place scrolled down more than half a screen, or always with VoiceOver,
    /// whose way to the sidebar is on the button.
    private func showsCornerButton(on viewController: UIViewController?) -> Bool {
        guard let screen = viewController as? TopLevelScreen else { return false }
        if UIAccessibility.isVoiceOverRunning { return true }
        guard let scrollView = screen.scrollView else { return false }
        return scrollView.contentOffset.y + scrollView.adjustedContentInset.top > scrollView.bounds.height / 2
    }

    private func observeScrolling(of scrollView: UIScrollView?) {
        guard scrollView !== observedScrollView || (scrollView != nil && scrollObservation == nil) else { return }
        observedScrollView = scrollView
        scrollObservation = scrollView?.observe(\.contentOffset) { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let shows = self.showsCornerButton(on: self.topViewController)
                if shows != self.cornerButtonShown { self.setCornerButtonShown(shows, animated: true) }
            }
        }
    }

    /// Fades the corner button in or out; the stacked button moves into its place while it's out.
    private func setCornerButtonShown(_ shown: Bool, animated: Bool) {
        cornerButtonShown = shown
        stackedInCorner.isActive = false
        stackedAboveCorner.isActive = shown
        stackedInCorner.isActive = !shown
        // Aside with the screen, if the sidebar is open.
        let shift = CGAffineTransform(translationX: sidebarWidth * sidebarProgress, y: 0)
        let change = {
            self.cornerButton.alpha = shown ? 1 : 0
            self.cornerButton.transform = shown ? shift : CGAffineTransform(scaleX: 0.6, y: 0.6).concatenating(shift)
            self.view.layoutIfNeeded()
        }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState], animations: change)
        } else {
            change()
        }
    }

    /// Shows the button above the corner button as it should be for `viewController`; call
    /// when what it offers changes.
    func updateStackedButton(for viewController: UIViewController?, animated: Bool) {
        let button = viewController.flatMap { stackedButton?($0) }
        stackedButtonAction = button?.action
        if let button {
            stackedButtonView.configuration?.image = UIImage(systemName: button.systemImage)
            stackedButtonView.accessibilityLabel = button.accessibilityLabel
        }
        view.bringSubviewToFront(stackedButtonView)
        let change = { self.stackedButtonView.alpha = button == nil ? 0 : 1 }
        animated ? UIView.animate(withDuration: 0.25, animations: change) : change()
        keepSidebarBehind()
    }

    // MARK: Sidebar

    /// Whether the sidebar can open over what's showing: a top-level place, alone in the stack.
    private var canOpenSidebar: Bool {
        sidebar == nil && sidebarSections != nil && viewControllers.count == 1 && topViewController is TopLevelScreen
            && presentedViewController == nil
    }

    var isSidebarOpen: Bool { sidebar != nil }

    func openSidebar(animated: Bool) {
        guard canOpenSidebar, makeSidebar() != nil else { return }
        settleSidebar(open: true, animated: animated)
    }

    /// Closes the sidebar, if it's open.
    func closeSidebar(animated: Bool) {
        guard sidebar != nil else { return }
        settleSidebar(open: false, animated: animated)
    }

    /// Pushes `viewController`, from the sidebar if it's open: the new screen slides in over the
    /// screen and sidebar as they are, in one movement, and the sidebar is put away behind it.
    func pushClosingSidebar(_ viewController: UIViewController) {
        guard sidebar != nil, let from = topViewController,
              !UIAccessibility.isReduceMotionEnabled,
              let snapshot = view.snapshotView(afterScreenUpdates: false)
        else {
            closeSidebar(animated: false)
            return pushViewController(viewController, animated: true)
        }
        closeSidebar(animated: false)
        // The screen being left looks as it did with the sidebar open, until it's covered.
        snapshot.frame = from.view.bounds
        from.view.addSubview(snapshot)
        updateCornerButton(for: viewController, animated: false)
        pushViewController(viewController, animated: true)
        if let transition = transitionCoordinator {
            transition.animate(alongsideTransition: nil) { _ in snapshot.removeFromSuperview() }
        } else {
            snapshot.removeFromSuperview()
        }
    }

    /// Over the screen while the sidebar is open, moving with it: a tap on it closes the
    /// sidebar, and it casts a shadow onto the sidebar.
    private var sidebarCover: UIView?
    /// How far the screen has slid aside for the sidebar: 0 closed, 1 open.
    private var sidebarProgress: CGFloat = 0
    /// Where the sidebar was when the swipe moving it began.
    private var sidebarSwipeStart: CGFloat = 0
    private var sidebarWidth: CGFloat { SidebarView.width(in: view.bounds.width) }

    /// Puts the sidebar under the screen (and corner buttons), and the cover over them.
    private func keepSidebarBehind() {
        if let sidebar { view.sendSubviewToBack(sidebar) }
        if let sidebarCover { view.bringSubviewToFront(sidebarCover) }
    }

    private func makeSidebar() -> SidebarView? {
        guard let sections = sidebarSections?() else { return nil }
        view.endEditing(true)
        let sidebar = SidebarView(
            frame: CGRect(x: 0, y: 0, width: sidebarWidth, height: view.bounds.height),
            sections: sections, accent: sidebarAccent?() ?? Theme.Color.accent
        )
        sidebar.onSelect = { [unowned self] item in
            item.action()
            closeSidebar(animated: true)
        }
        sidebar.onDismiss = { [unowned self] in closeSidebar(animated: true) }
        view.insertSubview(sidebar, at: 0)

        let cover = UIView(frame: view.bounds)
        cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        cover.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(sidebarCoverTapped)))
        let shadow = CAGradientLayer()
        shadow.colors = [UIColor.black.withAlphaComponent(0).cgColor, UIColor.black.withAlphaComponent(0.35).cgColor]
        shadow.startPoint = CGPoint(x: 0, y: 0.5)
        shadow.endPoint = CGPoint(x: 1, y: 0.5)
        shadow.frame = CGRect(x: -16, y: 0, width: 16, height: max(view.bounds.height, view.bounds.width))
        cover.layer.addSublayer(shadow)
        view.addSubview(cover)
        // In a wide window, the screen mustn't slide over the column beside it.
        view.clipsToBounds = true

        self.sidebar = sidebar
        sidebarCover = cover
        setSidebarProgress(0)
        return sidebar
    }

    @objc private func sidebarCoverTapped() {
        closeSidebar(animated: true)
    }

    /// Slides the screen, its corner buttons and the cover aside, uncovering the sidebar. Animatable.
    private func setSidebarProgress(_ progress: CGFloat) {
        sidebarProgress = progress
        let shift = CGAffineTransform(translationX: sidebarWidth * progress, y: 0)
        for subview in view.subviews where subview !== sidebar {
            subview.transform = shift
        }
        sidebar?.progress = progress
    }

    /// Stops the sidebar mid-animation, where it is on screen, for a swipe to take over.
    private func stopSidebarAnimations() {
        guard let sidebar else { return }
        let shown = sidebarCover?.layer.presentation()?.affineTransform().tx ?? sidebarWidth * sidebarProgress
        for subview in view.subviews {
            subview.layer.removeAllAnimations()
        }
        let progress = min(max(shown / max(sidebarWidth, 1), 0), 1)
        sidebar.stopAnimations(at: progress)
        setSidebarProgress(progress)
    }

    private func settleSidebar(open: Bool, animated: Bool, velocity: CGFloat = 0) {
        guard let sidebar else { return }
        let target: CGFloat = open ? 1 : 0
        let finish = {
            if open {
                UIAccessibility.post(notification: .screenChanged, argument: sidebar)
            } else {
                sidebar.removeFromSuperview()
                self.sidebarCover?.removeFromSuperview()
                if self.sidebar === sidebar {
                    self.sidebar = nil
                    self.sidebarCover = nil
                }
                self.setSidebarProgress(0)
                self.view.clipsToBounds = false
                UIAccessibility.post(notification: .screenChanged, argument: nil)
            }
        }
        guard animated, !UIAccessibility.isReduceMotionEnabled else {
            setSidebarProgress(target)
            return finish()
        }
        let distance = abs(target - sidebarProgress) * sidebarWidth
        let springVelocity = distance > 0 ? abs(velocity) / distance : 0
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: springVelocity, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.setSidebarProgress(target)
        } completion: { _ in
            // A swipe may have started on it again meanwhile.
            guard self.sidebar === sidebar, self.sidebarProgress == target else { return }
            finish()
        }
    }

    /// Opening from the left edge, or closing by dragging the screen back.
    @objc private func handleSidebarSwipe(_ gesture: UIPanGestureRecognizer) {
        let opening = gesture === sidebarEdgeSwipe
        switch gesture.state {
        case .began:
            if opening {
                guard makeSidebar() != nil else { return }
            } else {
                stopSidebarAnimations()
            }
            sidebarSwipeStart = sidebarProgress
        case .changed:
            guard sidebar != nil else { return }
            let x = gesture.translation(in: view).x / max(sidebarWidth, 1)
            setSidebarProgress(min(max(sidebarSwipeStart + x, 0), 1))
        case .ended:
            guard sidebar != nil else { return }
            let velocity = gesture.velocity(in: view).x
            // Open if it would coast past halfway.
            let open = projectedPosition(sidebarProgress * sidebarWidth, velocity: velocity) > sidebarWidth / 2
            settleSidebar(open: open, animated: true, velocity: velocity)
        default:
            settleSidebar(open: !opening, animated: true)
        }
    }

    // MARK: Gesture delegate

    private func isContentPop(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard #available(iOS 26, *) else { return false }
        return gestureRecognizer === interactiveContentPopGestureRecognizer
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === sidebarEdgeSwipe {
            return canOpenSidebar
        }
        if gestureRecognizer === sidebarCloseSwipe {
            // Sideways only, so the sidebar still scrolls.
            let velocity = sidebarCloseSwipe.velocity(in: view)
            return sidebar != nil && velocity.x < 0 && abs(velocity.x) > abs(velocity.y)
        }
        if gestureRecognizer === forwardSwipe {
            return interactivePush == nil && sidebar == nil && presentedViewController == nil && forwardTarget != nil
        }
        if isContentPop(gestureRecognizer), topViewController is EdgeOnlySwipeBack {
            return false
        }
        return viewControllers.count > 1
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard isContentPop(gestureRecognizer) else { return true }

        // Inside a sideways-scrolled view (a code block), dragging right scrolls it back instead.
        var view = touch.view
        while let current = view {
            if let scrollView = current as? UIScrollView,
               scrollView.contentSize.width > scrollView.bounds.width,
               scrollView.contentOffset.x > -scrollView.adjustedContentInset.left {
                return false
            }
            view = current.superview
        }
        return true
    }

    // MARK: Swipe forward

    private enum ForwardTarget {
        case screen(UIViewController)
        case browser(UIViewController)
    }

    /// What the swipe forward brings back: the screen last left with back, or else the browser
    /// last closed.
    private var forwardTarget: ForwardTarget? {
        // Screens that have since gone elsewhere (into the side column when the window widened) can't come back.
        forwardStack.removeAll { $0.parent != nil }
        if let screen = forwardStack.last { return .screen(screen) }
        if let browser = forwardBrowser, browser.presentingViewController == nil { return .browser(browser) }
        return nil
    }

    /// Presents a browser (Safari) that the swipe forward can bring back once it's closed.
    /// Opening it is opening something new, so what was ahead is forgotten.
    func presentBrowser(_ browser: UIViewController) {
        forwardStack.removeAll()
        forwardBrowser = browser
        present(browser, animated: true)
    }

    /// Takes note of how the stack changed: going back keeps what was left to go forward to,
    /// opening something else forgets it. Switching the root keeps it.
    private func stackDidChange(to stack: [UIViewController]) {
        defer { shownStack = stack }
        let old = shownStack
        if stack.count < old.count, zip(stack, old).allSatisfy({ $0 === $1 }) {
            forwardStack.append(contentsOf: old[stack.count...].reversed())
            forwardStack = Array(forwardStack.suffix(10))
        } else if stack.count > old.count, zip(stack, old).allSatisfy({ $0 === $1 }) {
            if let pushing = forwardPushing, stack.last === pushing {
                forwardPushing = nil
            } else {
                forwardStack.removeAll()
                forwardBrowser = nil
            }
        }
    }

    @objc private func handleForwardSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        let width = max(view.bounds.width, 1)
        let progress = min(max(-gesture.translation(in: view).x / width, 0), 1)

        switch gesture.state {
        case .began:
            switch forwardTarget {
            case .screen(let next):
                forwardStack.removeLast()
                forwardPushing = next
                interactivePush = UIPercentDrivenInteractiveTransition()
                pushViewController(next, animated: true)
            case .browser(let browser):
                present(browser, animated: true)
            case nil:
                break
            }
        case .changed:
            interactivePush?.update(progress)
        case .ended:
            // Go if it would coast past halfway.
            let velocity = -gesture.velocity(in: view).x
            if projectedPosition(progress * width, velocity: velocity) > width / 2 {
                interactivePush?.finish()
            } else {
                cancelForwardPush()
            }
            interactivePush = nil
        default:
            cancelForwardPush()
            interactivePush = nil
        }
    }

    private func cancelForwardPush() {
        guard let interactivePush else { return }
        interactivePush.cancel()
        if let pushing = forwardPushing {
            forwardStack.append(pushing)
            forwardPushing = nil
        }
    }

    // MARK: UINavigationControllerDelegate

    /// Called once a screen has finished appearing (after any push, pop or swipe back).
    var onDidShow: ((UIViewController) -> Void)?

    func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        stackDidChange(to: viewControllers)
        // Its list is surely loaded by now, to follow.
        if viewController is TopLevelScreen { updateCornerButton(for: viewController, animated: true) }
        onDidShow?(viewController)
    }

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        updateCornerButton(for: viewController, animated: animated)
        setNavigationBarHidden(!(viewController is ShowsNavigationBar), animated: animated)
        // An interactive swipe that's abandoned leaves the previous screen showing.
        transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
            guard context.isCancelled, let self else { return }
            updateCornerButton(for: topViewController, animated: true)
            setNavigationBarHidden(!(topViewController is ShowsNavigationBar), animated: true)
        }
    }

    func navigationController(
        _ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationController.Operation,
        from fromVC: UIViewController,
        to toVC: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        guard operation == .push else { return nil }
        // The interactive swipe-forward needs a custom animation; UIKit's own push can't be driven.
        if interactivePush != nil { return SlideTransition() }

        // Opening a story's comments from a list: the row grows into the comments header.
        if !UIAccessibility.isReduceMotionEnabled,
           let destination = toVC as? StoryTransitionDestination,
           let (card, title) = (fromVC as? StoryTransitionSource)?.transitionViews(forStory: destination.transitionStoryID) {
            return StoryTransition(card: card, title: title)
        }
        return nil
    }

    func navigationController(
        _ navigationController: UINavigationController,
        interactionControllerFor animationController: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        animationController is SlideTransition ? interactivePush : nil
    }
}

/// A push that looks like UIKit's: the new screen slides in from the right over the old one,
/// which moves left at a slower pace and dims.
private final class SlideTransition: NSObject, UIViewControllerAnimatedTransitioning {
    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.35
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let from = context.view(forKey: .from), let to = context.view(forKey: .to),
              let toVC = context.viewController(forKey: .to)
        else {
            context.completeTransition(false)
            return
        }

        let container = context.containerView
        let width = container.bounds.width
        to.frame = context.finalFrame(for: toVC)

        let dimming = UIView(frame: container.bounds)
        dimming.backgroundColor = .black
        dimming.alpha = 0
        container.addSubview(dimming)
        container.addSubview(to)

        to.transform = CGAffineTransform(translationX: width, y: 0)
        to.layer.shadowColor = UIColor.black.cgColor
        to.layer.shadowOpacity = 0.25
        to.layer.shadowRadius = 8

        let curve: UIView.AnimationOptions = context.isInteractive ? .curveLinear : .curveEaseOut
        UIView.animate(withDuration: transitionDuration(using: context), delay: 0, options: curve) {
            to.transform = .identity
            from.transform = CGAffineTransform(translationX: -width * 0.3, y: 0)
            dimming.alpha = 0.2
        } completion: { _ in
            let cancelled = context.transitionWasCancelled
            from.transform = .identity
            to.transform = .identity
            to.layer.shadowOpacity = 0
            dimming.removeFromSuperview()
            if cancelled { to.removeFromSuperview() }
            context.completeTransition(!cancelled)
        }
    }
}
