import UIKit

/// Top of the saved list, which doubles as the profile page: who's signed in,
/// how much is saved, and the way into settings.
final class ProfileHeaderView: UICollectionReusableView {
    var onSettings: (() -> Void)?
    /// Tapping "Not signed in".
    var onSignIn: (() -> Void)?
    private var isSignedIn = false

    private let nameLabel = UILabel()
    private let detailLabel = UILabel()
    private let settingsButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.backgroundDark

        nameLabel.font = Theme.Font.title(isPad: false)
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
        settingsButton.configuration = config
        settingsButton.accessibilityLabel = "Settings"
        settingsButton.accessibilityIdentifier = "saved.settings"
        settingsButton.addAction(UIAction { [weak self] _ in self?.onSettings?() }, for: .touchUpInside)
        settingsButton.setContentHuggingPriority(.required, for: .horizontal)

        nameLabel.isUserInteractionEnabled = true
        nameLabel.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(nameTapped)))

        let text = UIStackView(arrangedSubviews: [nameLabel, detailLabel])
        text.axis = .vertical
        text.spacing = 4

        let row = UIStackView(arrangedSubviews: [text, settingsButton])
        row.alignment = .center
        row.spacing = Theme.padding
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        let padding = Theme.padding
        NSLayoutConstraint.activate([
            row.topAnchor.constraint(equalTo: topAnchor, constant: padding * 2),
            row.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -padding * 2),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: padding),
            row.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -padding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func nameTapped() {
        if !isSignedIn { onSignIn?() }
    }

    /// - Parameter username: The signed-in HN user, or nil.
    func configure(username: String?, savedCount: Int) {
        isSignedIn = username != nil
        nameLabel.text = username ?? "Not signed in"
        nameLabel.alpha = username == nil ? 0.6 : 1
        nameLabel.accessibilityTraits = username == nil ? [.header, .button] : .header
        nameLabel.accessibilityHint = username == nil ? "Signs in to Hacker News" : nil
        detailLabel.text = savedCount == 1 ? "1 saved story" : "\(savedCount) saved stories"
    }
}
