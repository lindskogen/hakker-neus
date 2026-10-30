import UIKit

/// Orange header above the comments (`CommentsListItemHeader.tsx`).
final class StoryHeaderCell: UICollectionViewListCell {
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()
    /// The text of self posts (Ask HN etc), with tappable links.
    private let bodyView = CommentBodyView()

    var onLinkTap: ((URL) -> Void)? {
        get { bodyView.onLinkTap }
        set { bodyView.onLinkTap = newValue }
    }

    var linkMenu: ((URL, UIView) -> UIMenu)? {
        get { bodyView.linkMenu }
        set { bodyView.linkMenu = newValue }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.applyTextShadow()

        authorLabel.font = Theme.Font.body()
        authorLabel.textColor = .white
        authorLabel.numberOfLines = 0
        titleLabel.adjustsFontForContentSizeCategory = true
        authorLabel.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [titleLabel, authorLabel, bodyView])
        stack.setCustomSpacing(Theme.padding, after: authorLabel)
        stack.axis = .vertical
        stack.spacing = Theme.padding / 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        let minHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        minHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            minHeight,
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.padding * 2),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -Theme.padding * 2),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.padding),
            // Same as story rows, so the title wraps the same and the shared-element transition lines up.
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.padding * 3),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// The title, for the transition from a story row.
    var titleView: UIView { titleLabel }

    func configure(with story: Story, body: CommentBody?, score: Int? = nil, isUpvoted: Bool = false) {
        if let body, !body.blocks.isEmpty {
            bodyView.configure(with: body)
            bodyView.isHidden = false
        } else {
            bodyView.isHidden = true
        }

        titleLabel.font = Theme.Font.title(isPad: traitCollection.userInterfaceIdiom == .pad)
        titleLabel.text = story.title
        let points = score.map { isUpvoted ? "▲ \($0) points" : "\($0) points" }
        let byline = [points, story.author.map { "by \($0)" }, story.displayDomain].compactMap { $0 }
        authorLabel.text = byline.joined(separator: " · ")
        authorLabel.isHidden = byline.isEmpty

        // With self-post text, let VoiceOver reach its links instead of reading the header as one element.
        isAccessibilityElement = bodyView.isHidden
        titleLabel.accessibilityTraits = .header
        accessibilityLabel = story.title
        accessibilityValue = byline.joined(separator: ", ")
        accessibilityTraits = story.url == nil ? [.header] : [.header, .link]
        accessibilityIdentifier = "comments.header"
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = Theme.Color.accent
        backgroundConfiguration = background
        contentView.alpha = state.isHighlighted ? 0.4 : 1
    }
}

/// Full-height loading, empty or error state shown below the header.
final class StatusCell: UICollectionViewListCell {
    private let stateView = FullPageStateView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        stateView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stateView)
        NSLayoutConstraint.activate([
            stateView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stateView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            stateView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stateView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stateView.heightAnchor.constraint(greaterThanOrEqualToConstant: 400),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with state: FullPageStateView.State) {
        stateView.state = state
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = Theme.Color.backgroundDark
        backgroundConfiguration = background
    }
}
