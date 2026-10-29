import UIKit

/// A row on the front page (`ListItem.tsx`): title on an orange background,
/// the score faded in the bottom corner and a heart when saved.
///
/// Swipe right to save (heart), swipe left to open the comments (comment count).
final class StoryCell: UICollectionViewListCell {
    var onToggleSaved: (() -> Void)?
    var onOpenComments: (() -> Void)?

    /// The moving part of the row. The swipe actions sit behind it.
    private let rowView = UIView()
    private let titleLabel = UILabel()
    private let scoreLabel = UILabel()
    private let savedHeartView = UIImageView(image: UIImage(systemName: "heart.fill"))

    private let saveActionView = UIImageView()
    private let commentCountLabel = UILabel()

    private var rowColor: UIColor = Theme.Color.backgroundOrange
    private var storyID: Story.ID?
    private var isSaved = false
    private var armedAction: StorySwipe.Action?
    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private let horizontalOnly = HorizontalPanDelegate()

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.applyTextShadow()

        scoreLabel.font = Theme.Font.body(size: 30)
        scoreLabel.textColor = .white
        scoreLabel.alpha = 0.3
        scoreLabel.applyTextShadow()

        savedHeartView.tintColor = .white
        savedHeartView.preferredSymbolConfiguration = .init(pointSize: 26)

        saveActionView.tintColor = .white
        saveActionView.preferredSymbolConfiguration = .init(pointSize: 40)

        commentCountLabel.font = Theme.Font.body(size: 50)
        commentCountLabel.textColor = .white
        commentCountLabel.applyTextShadow()

        for view in [saveActionView, commentCountLabel, rowView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        for view in [titleLabel, scoreLabel, savedHeartView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview(view)
        }

        let padding = Theme.padding
        let minHeight = rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        minHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            rowView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            minHeight,

            titleLabel.topAnchor.constraint(equalTo: rowView.topAnchor, constant: padding * 2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: rowView.bottomAnchor, constant: -padding * 2),
            titleLabel.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -padding * 3),

            scoreLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -padding),
            scoreLabel.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -padding),

            savedHeartView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -padding),
            savedHeartView.topAnchor.constraint(equalTo: rowView.topAnchor, constant: padding),

            saveActionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding * 2),
            saveActionView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            commentCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding * 2),
            commentCountLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        let swipePan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        swipePan.delegate = horizontalOnly
        addGestureRecognizer(swipePan)

        apply(StorySwipe(translation: 0))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// - Parameters:
    ///   - showsSavedBadge: Whether a saved story shows the faded heart in its corner.
    ///     Off in the saved list, where every row is saved.
    ///   - extraAccessibilityActions: Screen-level actions VoiceOver should offer on every row.
    func configure(
        with story: Story,
        backgroundColor: UIColor,
        isSaved: Bool,
        showsSavedBadge: Bool = true,
        extraAccessibilityActions: [UIAccessibilityCustomAction] = []
    ) {
        let savedChanged = story.id == storyID && isSaved != self.isSaved
        storyID = story.id
        self.isSaved = isSaved

        rowColor = backgroundColor
        rowView.backgroundColor = backgroundColor
        titleLabel.font = Theme.Font.title(isPad: traitCollection.userInterfaceIdiom == .pad)
        titleLabel.text = story.title
        scoreLabel.text = "\(story.score)"
        commentCountLabel.text = "\(story.commentCount)"

        // Fade the saved heart in or out once the row has settled back, like the RN app.
        let heartAlpha: CGFloat = isSaved && showsSavedBadge ? 0.3 : 0
        if savedChanged {
            UIView.animate(withDuration: 0.4, delay: 0.3, usingSpringWithDamping: 0.8, initialSpringVelocity: 0) {
                self.savedHeartView.alpha = heartAlpha
            }
        } else {
            savedHeartView.alpha = heartAlpha
        }

        isAccessibilityElement = true
        accessibilityLabel = story.title
        accessibilityValue = "\(story.score) points, \(story.commentCount) comments" + (isSaved ? ", saved" : "")
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Open Comments") { [weak self] _ in
                self?.onOpenComments?()
                return true
            },
            UIAccessibilityCustomAction(name: isSaved ? "Unsave" : "Save") { [weak self] _ in
                self?.onToggleSaved?()
                return true
            },
        ] + extraAccessibilityActions
        setNeedsUpdateConfiguration()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        rowView.layer.removeAllAnimations()
        apply(StorySwipe(translation: 0))
        armedAction = nil
        storyID = nil
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = Theme.Color.backgroundDark
        backgroundConfiguration = background
        // Like TouchableOpacity: fade the content while pressed.
        rowView.alpha = state.isHighlighted ? 0.4 : 1
    }

    // MARK: Swiping

    @objc private func handlePan(_ pan: UIPanGestureRecognizer) {
        let swipe = StorySwipe(translation: pan.translation(in: self).x)

        switch pan.state {
        case .began:
            // Chosen here rather than in configure(), which runs again as soon as the save lands,
            // while the row is still springing back over this icon.
            saveActionView.image = UIImage(systemName: isSaved ? "heart.slash.fill" : "heart.fill")
            haptics.prepare()
            armedAction = nil
            apply(swipe)
        case .changed:
            apply(swipe)
            if swipe.armedAction != armedAction {
                armedAction = swipe.armedAction
                if armedAction != nil { haptics.impactOccurred() }
            }
        case .ended:
            switch swipe.armedAction {
            case .comments:
                onOpenComments?()
                settle()
            case .save:
                onToggleSaved?()
                settle(delay: 0.1)
            case nil:
                settle()
            }
            armedAction = nil
        default:
            settle()
            armedAction = nil
        }
    }

    private func apply(_ swipe: StorySwipe) {
        rowView.transform = CGAffineTransform(translationX: swipe.offset, y: 0)
        saveActionView.transform = CGAffineTransform(translationX: swipe.heartTranslation, y: 0)
        saveActionView.alpha = swipe.heartAlpha
        // Never scale all the way to zero; a singular transform can't be animated back.
        let scale = max(swipe.commentCountScale, 0.001)
        commentCountLabel.transform = CGAffineTransform(scaleX: scale, y: scale)
    }

    private func settle(delay: TimeInterval = 0) {
        UIView.animate(withDuration: 0.35, delay: delay, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.apply(StorySwipe(translation: 0))
        }
    }
}

/// Lets a pan begin only for mostly horizontal drags, so vertical drags scroll the list,
/// and leaves touches near the screen edges to the navigation edge swipes.
private final class HorizontalPanDelegate: NSObject, UIGestureRecognizerDelegate {
    private let edgeZone: CGFloat = 24

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard let window = touch.window else { return true }
        let x = touch.location(in: window).x
        return x > edgeZone && x < window.bounds.width - edgeZone
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: pan.view)
        return abs(velocity.x) > abs(velocity.y)
    }
}

/// Spinner shown under the list while the next page loads.
final class LoadingFooterView: UICollectionReusableView {
    private let spinner = UIActivityIndicatorView(style: .large)

    override init(frame: CGRect) {
        super.init(frame: frame)
        spinner.color = .white
        spinner.hidesWhenStopped = true
        spinner.translatesAutoresizingMaskIntoConstraints = false
        addSubview(spinner)
        accessibilityIdentifier = "stories.footer"
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: centerXAnchor),
            spinner.topAnchor.constraint(equalTo: topAnchor, constant: Theme.padding * 2),
            spinner.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Theme.padding * 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var isLoading = false {
        didSet { isLoading ? spinner.startAnimating() : spinner.stopAnimating() }
    }
}

extension UIView {
    /// The faint shadow the RN app puts behind white text on orange.
    func applyTextShadow() {
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.1
        layer.shadowRadius = 1
        layer.shadowOffset = .zero
    }
}
