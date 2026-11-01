import UIKit

/// A row on the front page (`ListItem.tsx`): title on an orange background,
/// the score faded in the bottom corner and a heart when saved.
///
/// Swipe right to save (heart), swipe left to open the comments (comment count).
final class StoryCell: UICollectionViewListCell {
    var onToggleSaved: (() -> Void)?
    var onToggleUpvote: (() -> Void)?
    var onOpenComments: (() -> Void)?
    var onSwipeBegan: (() -> Void)?

    /// The moving part of the row. The swipe actions sit behind it.
    private let rowView = UIView()
    private let titleLabel = UILabel()
    private let domainLabel = UILabel()
    let scoreLabel = UILabel()
    private let savedHeartView = UIImageView(image: UIImage(systemName: "heart.fill"))

    private let saveActionView = UIImageView()
    /// Behind the row; turns blue once a right swipe reaches the upvote stage.
    private let actionBackground = UIView()
    private var isUpvoted = false
    let commentCountLabel = UILabel()

    private var rowColor: UIColor = Theme.Color.accent
    private var storyID: Story.ID?
    private var isSaved = false
    private var armedAction: StorySwipe.Action?
    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private let horizontalOnly = HorizontalPanDelegate()
    private var isCompact = false
    private var titleTop: NSLayoutConstraint!
    private var titleTrailing: NSLayoutConstraint!
    private var minHeight: NSLayoutConstraint!
    private var bottomInsets: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.applyTextShadow()

        domainLabel.font = Theme.Font.body(size: 14, style: .subheadline)
        // Next to the score, the domain is the one that gives way.
        domainLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        domainLabel.textColor = UIColor.white.withAlphaComponent(0.7)
        domainLabel.applyTextShadow()

        // The score and swipe count are decoration; cap them so they don't take over the row.
        scoreLabel.font = Theme.Font.body(size: 30, style: .title1, maximum: 40)
        scoreLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        scoreLabel.textColor = .white
        scoreLabel.alpha = 0.3
        scoreLabel.applyTextShadow()

        savedHeartView.tintColor = .white
        savedHeartView.preferredSymbolConfiguration = .init(pointSize: 26)

        saveActionView.tintColor = .white
        saveActionView.preferredSymbolConfiguration = .init(pointSize: 40)

        commentCountLabel.font = Theme.Font.body(size: 50, style: .largeTitle, maximum: 64)
        // Must fit in the gap the row uncovers; long counts shrink rather than hide under the row.
        commentCountLabel.adjustsFontSizeToFitWidth = true
        commentCountLabel.minimumScaleFactor = 0.4
        commentCountLabel.textAlignment = .right
        commentCountLabel.textColor = .white
        commentCountLabel.applyTextShadow()

        for label in [titleLabel, domainLabel, scoreLabel, commentCountLabel] {
            label.adjustsFontForContentSizeCategory = true
        }

        actionBackground.backgroundColor = .clear
        for view in [actionBackground, saveActionView, commentCountLabel, rowView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        for view in [titleLabel, domainLabel, scoreLabel, savedHeartView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            rowView.addSubview(view)
        }

        let padding = Theme.padding
        minHeight = rowView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        minHeight.priority = .defaultHigh
        titleTop = titleLabel.topAnchor.constraint(equalTo: rowView.topAnchor, constant: padding * 2)
        titleTrailing = titleLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -padding * 3)
        bottomInsets = [
            domainLabel.bottomAnchor.constraint(lessThanOrEqualTo: rowView.bottomAnchor, constant: -padding * 2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: rowView.bottomAnchor, constant: -padding * 2),
        ]

        NSLayoutConstraint.activate([
            actionBackground.topAnchor.constraint(equalTo: contentView.topAnchor),
            actionBackground.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            actionBackground.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            actionBackground.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            rowView.topAnchor.constraint(equalTo: contentView.topAnchor),
            rowView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            rowView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            rowView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            minHeight,

            titleTop,
            titleLabel.leadingAnchor.constraint(equalTo: rowView.leadingAnchor, constant: padding),
            titleTrailing,

            // Not in a stack with the title: a stack would stretch it to the title's full width,
            // leaving the score no room. On its own it only has to keep its text clear of the score.
            domainLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            domainLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            domainLabel.trailingAnchor.constraint(lessThanOrEqualTo: scoreLabel.leadingAnchor, constant: -padding),

            scoreLabel.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -padding),
            scoreLabel.bottomAnchor.constraint(equalTo: rowView.bottomAnchor, constant: -padding),

            savedHeartView.trailingAnchor.constraint(equalTo: rowView.trailingAnchor, constant: -padding),
            savedHeartView.topAnchor.constraint(equalTo: rowView.topAnchor, constant: padding),

            saveActionView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding * 2),
            saveActionView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            commentCountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            commentCountLabel.widthAnchor.constraint(lessThanOrEqualToConstant: StorySwipe.commentsThreshold - padding * 2),
            commentCountLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ] + bottomInsets)

        let swipePan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        swipePan.delegate = horizontalOnly
        addGestureRecognizer(swipePan)

        apply(StorySwipe(translation: 0))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The coloured card and title, for the transition into the comments header.
    var transitionViews: (card: UIView, title: UIView) { (rowView, titleLabel) }

    /// - Parameters:
    ///   - showsSavedBadge: Whether a saved story shows the faded heart in its corner.
    ///     Off in the saved list, where every row is saved.
    ///   - compact: A quieter row for lists inside other screens (a user's stories): a smaller
    ///     title and one dim line with the domain, points, comments and age, and no big score.
    ///   - extraAccessibilityActions: Screen-level actions VoiceOver should offer on every row.

    func configure(
        with story: Story,
        backgroundColor: UIColor,
        isSaved: Bool,
        isUpvoted: Bool = false,
        score: Int? = nil,
        isVisited: Bool = false,
        isActive: Bool = false,
        canUpvote: Bool = true,
        newComments: Int? = nil,
        showsSavedBadge: Bool = true,
        compact: Bool = false,
        extraAccessibilityActions: [UIAccessibilityCustomAction] = []
    ) {
        let savedChanged = story.id == storyID && isSaved != self.isSaved
        storyID = story.id
        self.isSaved = isSaved
        self.isUpvoted = isUpvoted
        self.canUpvote = canUpvote

        // The story open beside the list (iPad) turns black.
        let backgroundColor = isActive ? Palette.activeStoryBackground : backgroundColor
        rowColor = backgroundColor
        rowView.backgroundColor = backgroundColor
        setCompact(compact)
        titleLabel.text = story.title
        // Read stories fade back, so unread ones stand out.
        titleLabel.alpha = isVisited ? 0.55 : 1
        let score = score ?? story.score
        let details = compact
            ? [
                story.displayDomain, (isUpvoted ? "▲ " : "") + (score == 1 ? "1 point" : "\(score) points"),
                story.commentCount == 1 ? "1 comment" : "\(story.commentCount) comments", RelativeTime.string(from: story.time),
            ]
            .compactMap { $0 }
            : [story.displayDomain, newComments.map { "\($0) new" }].compactMap { $0 }
        domainLabel.text = details.joined(separator: " · ")
        domainLabel.isHidden = details.isEmpty
        // Empty rather than hidden in compact rows, so it takes no width from the details line.
        scoreLabel.text = compact ? nil : isUpvoted ? "▲ \(score)" : "\(score)"
        scoreLabel.alpha = isUpvoted ? 0.85 : 0.3
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
        accessibilityValue = [
            story.displayDomain, "\(score) points", isUpvoted ? "upvoted" : nil, "\(story.commentCount) comments",
            newComments.map { "\($0) new" }, isVisited ? "read" : nil, isSaved ? "saved" : nil, isActive ? "open" : nil,
        ]
            .compactMap { $0 }
            .joined(separator: ", ")
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "Open Comments") { [weak self] _ in
                self?.onOpenComments?()
                return true
            },
            UIAccessibilityCustomAction(name: isSaved ? "Unsave" : "Save") { [weak self] _ in
                self?.onToggleSaved?()
                return true
            },
            UIAccessibilityCustomAction(name: isUpvoted ? "Unvote" : "Upvote") { [weak self] _ in
                self?.onToggleUpvote?()
                return true
            },
        ] + extraAccessibilityActions
        setNeedsUpdateConfiguration()
    }

    private func setCompact(_ compact: Bool) {
        let isPad = traitCollection.userInterfaceIdiom == .pad
        titleLabel.font = compact ? Theme.Font.light(size: isPad ? 24 : 20, style: .title3) : Theme.Font.title(isPad: isPad)
        guard compact != isCompact else { return }
        isCompact = compact
        let padding = Theme.padding
        domainLabel.font = compact ? Theme.Font.body(size: 13, style: .footnote) : Theme.Font.body(size: 14, style: .subheadline)
        domainLabel.textColor = UIColor.white.withAlphaComponent(compact ? 0.45 : 0.7)
        domainLabel.numberOfLines = compact ? 0 : 1
        titleTop.constant = compact ? padding * 1.5 : padding * 2
        titleTrailing.constant = compact ? -padding : -padding * 3
        minHeight.constant = compact ? 0 : 100
        for inset in bottomInsets { inset.constant = compact ? -padding * 1.5 : -padding * 2 }
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
        let swipe = StorySwipe(translation: pan.translation(in: self).x, canUpvote: canUpvote)

        switch pan.state {
        case .began:
            // Icons are chosen per swipe rather than in configure(), which runs again as soon as
            // the action lands, while the row is still springing back over them.
            swipeStartedSaved = isSaved
            swipeStartedUpvoted = isUpvoted
            onSwipeBegan?()
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
            case .upvote:
                onToggleUpvote?()
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

    private var canUpvote = true
    private var swipeStartedSaved = false
    private var swipeStartedUpvoted = false

    func apply(_ swipe: StorySwipe) {
        rowView.transform = CGAffineTransform(translationX: swipe.offset, y: 0)
        let upvoteStage = swipe.armedAction == .upvote
        saveActionView.image = UIImage(systemName: upvoteStage
            ? (swipeStartedUpvoted ? "arrow.uturn.down" : "arrow.up")
            : (swipeStartedSaved ? "heart.slash.fill" : "heart.fill"))
        actionBackground.backgroundColor = upvoteStage ? Palette.upvoteStage : .clear
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
