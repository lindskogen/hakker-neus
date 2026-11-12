import UIKit

/// Top of the saved list: its title, how much is saved, and tabs for stories and comments.
final class SavedHeaderView: UICollectionReusableView {
    /// Switching between saved stories and saved comments.
    var onTab: ((SavedStoriesViewController.Tab) -> Void)? {
        get { tabs.onSelect }
        set { tabs.onSelect = newValue }
    }
    private let tabs = TextTabsView<SavedStoriesViewController.Tab>()

    private let titleLabel = UILabel()
    private let detailLabel = UILabel()
    private var leadingConstraint: NSLayoutConstraint!
    private var trailingConstraint: NSLayoutConstraint!

    /// Space on each side: the system margin the Settings app uses (16pt, or 20pt on the widest
    /// iPhones), passed in from the list's view controller.
    var horizontalMargin: CGFloat = 16 {
        didSet {
            leadingConstraint.constant = horizontalMargin
            trailingConstraint.constant = -horizontalMargin
        }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.backgroundDark

        titleLabel.font = Theme.Font.title(isWide: false)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.accessibilityTraits = .header

        detailLabel.font = Theme.Font.body(size: 14, style: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.6)

        titleLabel.text = "Saved"

        let text = UIStackView(arrangedSubviews: [titleLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 4

        let row = UIStackView(arrangedSubviews: [text])
        row.alignment = .center
        row.spacing = Theme.padding
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        tabs.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabs)

        let padding = Theme.padding
        leadingConstraint = row.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: horizontalMargin)
        trailingConstraint = row.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -horizontalMargin)
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: padding * 2),
            leadingConstraint,
            trailingConstraint,
            tabs.topAnchor.constraint(equalTo: row.bottomAnchor, constant: padding),
            tabs.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor),
            tabs.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor),
            tabs.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(savedCount: Int, savedCommentCount: Int, tab: SavedStoriesViewController.Tab) {
        tabs.selected = tab
        let stories = savedCount == 1 ? "1 saved story" : "\(savedCount) saved stories"
        let comments = savedCommentCount == 1 ? "1 comment" : "\(savedCommentCount) comments"
        detailLabel.text = savedCommentCount > 0 ? "\(stories) · \(comments)" : stories
    }
}
