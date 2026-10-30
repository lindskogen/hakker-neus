import UIKit

/// Screens where swiping right in the content area does something else (like saving a story row),
/// so only the edge swipe goes back.
@MainActor
protocol EdgeOnlySwipeBack {}

/// Screens with a screen to their right, reached by swiping in from the right edge.
@MainActor
protocol ForwardNavigating {
    var forwardViewController: UIViewController? { get }
}

/// Navigation controller with a hidden bar that keeps the interactive swipe-back gestures,
/// and adds an interactive swipe-forward from the right edge.
///
/// UIKit disables both pop gestures while the bar is hidden. Taking over their delegates
/// re-enables them: the edge swipe everywhere, and on iOS 26 also the swipe from anywhere in
/// the content area. iOS 18–25 only get the edge swipe.
final class NavigationController: UINavigationController, UIGestureRecognizerDelegate, UINavigationControllerDelegate {
    private let forwardSwipe = UIScreenEdgePanGestureRecognizer()
    private var interactivePush: UIPercentDrivenInteractiveTransition?

    /// The lower-right button (lower-left if set for left hands), above every screen so it stays
    /// put while they change underneath: a hamburger on the front page (to the profile), a close
    /// button on the profile (back).
    private let cornerButton = UIButton(type: .system)
    private var cornerButtonLeading: NSLayoutConstraint!
    private var cornerButtonTrailing: NSLayoutConstraint!

    /// Puts the corner button in the lower-left corner instead of the lower-right.
    var cornerButtonOnLeft = false {
        didSet { placeCornerButton() }
    }
    /// Called when the corner button is tapped, with the screen it was tapped on.
    var onCornerButton: ((UIViewController) -> Void)?
    /// Screens that show the corner button, and whether it shows as close on them.
    var cornerButtonMode: (UIViewController) -> CornerButtonMode = { _ in .hidden }

    enum CornerButtonMode: Equatable {
        case menu
        case close
        case hidden
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        view.backgroundColor = Theme.Color.backgroundDark
        delegate = self

        interactivePopGestureRecognizer?.delegate = self
        if #available(iOS 26, *) {
            // Apple documents this recognizer as "only for failure requirements", so this may need
            // revisiting in future iOS versions. Covered by NavigationUITests.
            interactiveContentPopGestureRecognizer?.delegate = self
        }

        configureCornerButton()

        forwardSwipe.edges = .right
        forwardSwipe.delegate = self
        forwardSwipe.addTarget(self, action: #selector(handleForwardSwipe(_:)))
        view.addGestureRecognizer(forwardSwipe)
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    // MARK: Corner button

    private func configureCornerButton() {
        var config: UIButton.Configuration
        if #available(iOS 26, *) {
            config = .glass()
        } else {
            config = .filled()
            config.baseBackgroundColor = UIColor(white: 0.25, alpha: 0.9)
        }
        config.preferredSymbolConfigurationForImage = .init(pointSize: 18, weight: .semibold)
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        // The icon morphs between the hamburger and the close button (cross-fades before iOS 26).
        if #available(iOS 26, *) {
            config.symbolContentTransition = UISymbolContentTransition(.replace.downUp)
        }
        cornerButton.configuration = config
        cornerButton.accessibilityIdentifier = "cornerButton"
        cornerButton.alpha = 0
        cornerButton.addAction(UIAction { [unowned self] _ in
            if let top = topViewController { onCornerButton?(top) }
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
    }

    private func placeCornerButton() {
        guard isViewLoaded else { return }
        cornerButtonLeading.isActive = cornerButtonOnLeft
        cornerButtonTrailing.isActive = !cornerButtonOnLeft
    }

    /// Shows the corner button as it should be for `viewController`.
    func updateCornerButton(for viewController: UIViewController?, animated: Bool) {
        let mode = viewController.map(cornerButtonMode) ?? .hidden
        if mode != .hidden {
            let setIcon: () -> Void = {
                self.cornerButton.configuration?.image = UIImage(systemName: mode == .close ? "xmark" : "line.3.horizontal")
            }
            if #available(iOS 26, *) {
                setIcon()
            } else if animated {
                UIView.transition(with: cornerButton, duration: 0.25, options: .transitionCrossDissolve, animations: setIcon)
            } else {
                setIcon()
            }
            cornerButton.accessibilityLabel = mode == .close ? "Front Page" : "Profile and Saved Stories"
        }
        view.bringSubviewToFront(cornerButton)
        let change = { self.cornerButton.alpha = mode == .hidden ? 0 : 1 }
        animated ? UIView.animate(withDuration: 0.25, animations: change) : change()
    }

    // MARK: Gesture delegate

    private func isContentPop(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard #available(iOS 26, *) else { return false }
        return gestureRecognizer === interactiveContentPopGestureRecognizer
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === forwardSwipe {
            return interactivePush == nil && (topViewController as? ForwardNavigating)?.forwardViewController != nil
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

    @objc private func handleForwardSwipe(_ gesture: UIScreenEdgePanGestureRecognizer) {
        let width = max(view.bounds.width, 1)
        let progress = min(max(-gesture.translation(in: view).x / width, 0), 1)

        switch gesture.state {
        case .began:
            guard let next = (topViewController as? ForwardNavigating)?.forwardViewController else { return }
            interactivePush = UIPercentDrivenInteractiveTransition()
            pushViewController(next, animated: true)
        case .changed:
            interactivePush?.update(progress)
        case .ended:
            let velocity = gesture.velocity(in: view).x
            if progress > 0.4 || velocity < -500 {
                interactivePush?.finish()
            } else {
                interactivePush?.cancel()
            }
            interactivePush = nil
        default:
            interactivePush?.cancel()
            interactivePush = nil
        }
    }

    // MARK: UINavigationControllerDelegate

    func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        updateCornerButton(for: viewController, animated: animated)
        // An interactive swipe that's abandoned leaves the previous screen showing.
        transitionCoordinator?.notifyWhenInteractionChanges { [weak self] context in
            if context.isCancelled { self?.updateCornerButton(for: self?.topViewController, animated: true) }
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
