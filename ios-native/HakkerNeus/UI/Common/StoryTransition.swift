import UIKit

/// A list that can hand over a story row for the transition into its comments.
@MainActor
protocol StoryTransitionSource {
    /// The row's coloured card and its title.
    func transitionViews(forStory id: Int) -> (card: UIView, title: UIView)?
}

/// A screen with a story header to receive the row.
@MainActor
protocol StoryTransitionDestination: UIViewController {
    var transitionStoryID: Int { get }
    /// The header, its title and its colour. Only valid once the view has been laid out.
    func transitionViews() -> (header: UIView, title: UIView, color: UIColor)?
}

/// Push where a story row's orange card grows into the comments header (running up under the
/// status bar, like the header does) and its title glides into place, while the comments fade in.
final class StoryTransition: NSObject, UIViewControllerAnimatedTransitioning {
    private let card: UIView
    private let title: UIView

    init(card: UIView, title: UIView) {
        self.card = card
        self.title = title
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        0.5
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        guard let toVC = context.viewController(forKey: .to),
              let toView = context.view(forKey: .to)
        else {
            context.completeTransition(false)
            return
        }
        let container = context.containerView
        toView.frame = context.finalFrame(for: toVC)
        toView.alpha = 0
        container.addSubview(toView)
        toView.layoutIfNeeded()

        guard let (header, headerTitle, headerColor) = (toVC as? StoryTransitionDestination)?.transitionViews() else {
            // No header to land on (yet): plain fade.
            UIView.animate(withDuration: transitionDuration(using: context)) {
                toView.alpha = 1
            } completion: { _ in
                context.completeTransition(!context.transitionWasCancelled)
            }
            return
        }

        // The moving card: from the row to the header, extended up to the top of the screen.
        let headerFrame = header.convert(header.bounds, to: container)
        let movingCard = UIView(frame: card.convert(card.bounds, to: container))
        movingCard.backgroundColor = card.backgroundColor
        container.addSubview(movingCard)

        // The title: a copy of the header's, which may differ from the row's (dimmed when read).
        let titleStart = title.convert(title.bounds, to: container)
        let titleEnd = headerTitle.convert(headerTitle.bounds, to: container)
        let movingTitle = Self.copy(of: headerTitle) ?? title.snapshotView(afterScreenUpdates: false) ?? UIView()
        movingTitle.frame = CGRect(origin: titleStart.origin, size: titleEnd.size)
        container.addSubview(movingTitle)

        card.alpha = 0
        headerTitle.alpha = 0

        // Near the end, fade the card out over the real header (same colour and place) so the
        // header's byline appears smoothly instead of popping in when the card is removed.
        let duration = transitionDuration(using: context)
        UIView.animate(withDuration: duration * 0.35, delay: duration * 0.6, options: .curveEaseIn) {
            movingCard.alpha = 0
        }

        UIView.animate(
            withDuration: duration, delay: 0,
            usingSpringWithDamping: 0.9, initialSpringVelocity: 0
        ) {
            toView.alpha = 1
            movingCard.frame = CGRect(x: headerFrame.minX, y: 0, width: headerFrame.width, height: headerFrame.maxY)
            movingCard.backgroundColor = headerColor
            movingTitle.frame.origin = titleEnd.origin
        } completion: { _ in
            // The card has landed on the real header, same colour and shape: swap it out.
            self.card.alpha = 1
            headerTitle.alpha = 1
            movingCard.removeFromSuperview()
            movingTitle.removeFromSuperview()
            context.completeTransition(!context.transitionWasCancelled)
        }
    }

    private static func copy(of view: UIView) -> UIView? {
        guard let label = view as? UILabel else { return nil }
        let copy = UILabel()
        copy.attributedText = label.attributedText
        copy.numberOfLines = label.numberOfLines
        copy.textColor = label.textColor
        copy.font = label.font
        copy.layer.shadowColor = label.layer.shadowColor
        copy.layer.shadowOpacity = label.layer.shadowOpacity
        copy.layer.shadowRadius = label.layer.shadowRadius
        copy.layer.shadowOffset = label.layer.shadowOffset
        return copy
    }
}
