import UIKit

/// Top of the saved list, which doubles as the profile page: who's signed in,
/// how much is saved, and the way into settings.
final class ProfileHeaderView: UICollectionReusableView {
    var onSettings: (() -> Void)?
    var onSearch: (() -> Void)?
    /// Tapping "Sign in", shown when signed out.
    var onSignIn: (() -> Void)?
    /// Tapping your own name, when signed in.
    var onShowUser: ((String) -> Void)?
    /// Switching between saved stories and saved comments.
    var onTab: ((SavedStoriesViewController.Tab) -> Void)? {
        get { tabs.onSelect }
        set { tabs.onSelect = newValue }
    }
    private let tabs = TextTabsView<SavedStoriesViewController.Tab>()
    private var username: String?
    private var isSignedIn = false

    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let settingsButton = UIButton(type: .system)
    private let searchButton = UIButton(type: .system)
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

        nameLabel.font = Theme.Font.title(isWide: false)
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.textColor = .white
        nameLabel.numberOfLines = 0
        nameLabel.accessibilityTraits = .header

        detailLabel.font = Theme.Font.body(size: 14, style: .subheadline)
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.textColor = UIColor.white.withAlphaComponent(0.6)

        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: "gearshape")
        config.preferredSymbolConfigurationForImage = .init(pointSize: 20, weight: .regular)
        config.baseForegroundColor = .white
        // No built-in insets, so the gear sits as far from the right edge as the name does
        // from the left; the button stays 44pt wide for tapping, with the gear at its trailing edge.
        config.contentInsets = .zero
        settingsButton.configuration = config
        settingsButton.contentHorizontalAlignment = .trailing
        settingsButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        settingsButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.accessibilityIdentifier = "saved.settings"
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
        settingsButton.setContentHuggingPriority(.required, for: .horizontal)

        var searchConfig = config
        searchConfig.image = UIImage(systemName: "magnifyingglass")
        searchButton.configuration = searchConfig
        searchButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        searchButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        searchButton.accessibilityLabel = "Search"
        searchButton.accessibilityIdentifier = "saved.search"
        searchButton.addAction(UIAction { [weak self] _ in self?.onSearch?() }, for: .touchUpInside)
        searchButton.setContentHuggingPriority(.required, for: .horizontal)


        nameLabel.isUserInteractionEnabled = true
        nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(nameTapped)))

        let text = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 4

        let row = UIStackView(arrangedSubviews: [text, searchButton, settingsButton])
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

    @objc private func nameTapped() {
        if let username { onShowUser?(username) } else { onSignIn?() }
    }

    /// - Parameter username: The signed-in HN user, or nil.
    func configure(username: String?, savedCount: Int, savedCommentCount: Int, tab: SavedStoriesViewController.Tab) {
        tabs.selected = tab
        isSignedIn = username != nil
        self.username = username
        // Signed out, the name's place is an obvious way to sign in.
        nameLabel.text = username ?? "Sign in"
        nameLabel.textColor = username == nil ? Theme.Color.accent : .white
        nameLabel.accessibilityTraits = [.header, .button]
        nameLabel.accessibilityHint = username == nil ? "Signs in to Hacker News" : "Shows your Hacker News page"
        let stories = savedCount == 1 ? "1 saved story" : "\(savedCount) saved stories"
        let comments = savedCommentCount == 1 ? "1 comment" : "\(savedCommentCount) comments"
        detailLabel.text = savedCommentCount > 0 ? "\(stories) · \(comments)" : stories
    }
}
