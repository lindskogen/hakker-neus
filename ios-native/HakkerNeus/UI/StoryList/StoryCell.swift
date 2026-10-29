import UIKit

/// A row on the front page (`ListItem.tsx`): title on an orange background,
/// the score faded in the bottom corner and a heart when saved.
final class StoryCell: UICollectionViewListCell {
    private let titleLabel = UILabel()
    private let scoreLabel = UILabel()
    private let heartView = UIImageView(image: UIImage(systemName: "heart.fill"))
    private var rowColor: UIColor = Theme.Color.backgroundOrange

    override init(frame: CGRect) {
        super.init(frame: frame)

        titleLabel.textColor = .white
        titleLabel.numberOfLines = 0
        titleLabel.applyTextShadow()

        scoreLabel.font = Theme.Font.body(size: 30)
        scoreLabel.textColor = .white
        scoreLabel.alpha = 0.3
        scoreLabel.applyTextShadow()

        heartView.tintColor = .white
        heartView.alpha = 0.3
        heartView.preferredSymbolConfiguration = .init(pointSize: 26)

        for view in [titleLabel, scoreLabel, heartView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        let padding = Theme.padding
        let minHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 100)
        minHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            minHeight,
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding * 2),
            titleLabel.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -padding * 2),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: padding),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding * 3),

            scoreLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            scoreLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding),

            heartView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            heartView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: padding),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with story: Story, backgroundColor: UIColor, isSaved: Bool) {
        rowColor = backgroundColor
        titleLabel.font = Theme.Font.title(isPad: traitCollection.userInterfaceIdiom == .pad)
        titleLabel.text = story.title
        scoreLabel.text = "\(story.score)"
        heartView.isHidden = !isSaved

        accessibilityLabel = story.title
        accessibilityValue = "\(story.score) points, \(story.commentCount) comments" + (isSaved ? ", saved" : "")
        isAccessibilityElement = true
        setNeedsUpdateConfiguration()
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = rowColor
        backgroundConfiguration = background
        // Like TouchableOpacity: fade the content while pressed.
        contentView.alpha = state.isHighlighted ? 0.4 : 1
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
