import UIKit

/// Orange header above the comments (`CommentsListItemHeader.tsx`).
final class StoryHeaderCell: UICollectionViewListCell {
    private let titleLabel = UILabel()
    private let authorLabel = UILabel()

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

        let stack = UIStackView(arrangedSubviews: [titleLabel, authorLabel])
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
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.padding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with story: Story) {
        titleLabel.font = Theme.Font.title(isPad: traitCollection.userInterfaceIdiom == .pad)
        titleLabel.text = story.title
        let byline = [story.author.map { "by \($0)" }, story.displayDomain].compactMap { $0 }
        authorLabel.text = byline.joined(separator: " · ")
        authorLabel.isHidden = byline.isEmpty

        isAccessibilityElement = true
        accessibilityLabel = story.title
        accessibilityValue = byline.joined(separator: ", ")
        accessibilityTraits = story.url == nil ? [.header] : [.header, .link]
        accessibilityIdentifier = "comments.header"
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = Theme.Color.backgroundOrange
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
