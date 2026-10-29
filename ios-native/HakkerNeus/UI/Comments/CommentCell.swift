import UIKit

/// One comment (`CommentWithChildren.tsx`): indented by depth with a colored bar,
/// a header with author, OP badge and age, and the body text.
/// When collapsed the body is hidden and the header shows how many replies are hidden.
final class CommentCell: UICollectionViewListCell {
    struct Content {
        let comment: Comment
        let depth: Int
        let body: CommentBody
        let isOP: Bool
        let isCollapsed: Bool
        let hiddenReplies: Int
    }

    /// Indentation stops growing past this depth so deep threads stay readable.
    static let maxIndentDepth = 8

    private let topBorder = UIView()
    private let depthBar = UIView()
    private let authorLabel = UILabel()
    private let opBadge = PaddedLabel()
    private let collapsedLabel = UILabel()
    private let timeLabel = UILabel()
    private let bodyView = CommentBodyView()
    private let stack = UIStackView()
    private var indentConstraint: NSLayoutConstraint!
    private var time: Date?

    override init(frame: CGRect) {
        super.init(frame: frame)

        topBorder.backgroundColor = UIColor.white.withAlphaComponent(0.2)

        authorLabel.font = Theme.Font.medium(size: 13)
        authorLabel.textColor = .white

        opBadge.text = "OP"
        opBadge.font = Theme.Font.bold(size: 8)
        opBadge.textColor = .white
        opBadge.backgroundColor = UIColor.white.withAlphaComponent(0.13)
        opBadge.layer.cornerRadius = 3
        opBadge.clipsToBounds = true

        collapsedLabel.font = Theme.Font.medium(size: 13)
        collapsedLabel.textColor = UIColor.white.withAlphaComponent(0.5)

        timeLabel.font = Theme.Font.body(size: 13)
        timeLabel.textColor = .white
        timeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        let author = UIStackView(arrangedSubviews: [authorLabel, opBadge, collapsedLabel])
        author.spacing = 5
        author.alignment = .center

        let header = UIStackView(arrangedSubviews: [author, UIView(), timeLabel])
        header.alignment = .center

        stack.addArrangedSubview(header)
        stack.addArrangedSubview(bodyView)
        stack.axis = .vertical
        stack.spacing = Theme.padding

        for view in [topBorder, depthBar, stack] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }

        let padding = Theme.padding
        indentConstraint = topBorder.leadingAnchor.constraint(equalTo: contentView.leadingAnchor)
        let minHeight = contentView.heightAnchor.constraint(greaterThanOrEqualToConstant: 40)
        minHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            minHeight,
            indentConstraint,
            topBorder.topAnchor.constraint(equalTo: contentView.topAnchor),
            topBorder.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            topBorder.heightAnchor.constraint(equalToConstant: 1 / max(traitCollection.displayScale, 1)),

            depthBar.leadingAnchor.constraint(equalTo: topBorder.leadingAnchor),
            depthBar.widthAnchor.constraint(equalToConstant: 3),
            depthBar.topAnchor.constraint(equalTo: topBorder.bottomAnchor, constant: padding),
            depthBar.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -padding),

            stack.leadingAnchor.constraint(equalTo: depthBar.trailingAnchor, constant: padding),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -padding),
            stack.topAnchor.constraint(equalTo: depthBar.topAnchor, constant: padding / 2),
            stack.bottomAnchor.constraint(equalTo: depthBar.bottomAnchor, constant: -padding / 2),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with content: Content) {
        indentConstraint.constant = Theme.padding * CGFloat(min(content.depth, Self.maxIndentDepth))
        depthBar.backgroundColor = Palette.commentDepth(content.depth)

        let author = content.comment.author ?? "deleted"
        authorLabel.text = author
        opBadge.isHidden = !content.isOP
        time = content.comment.time
        updateTime()

        // Rebuilding the body is wasted work while collapsed; it's rebuilt on expand.
        if !content.isCollapsed {
            bodyView.configure(with: content.body)
        }
        bodyView.isHidden = content.isCollapsed
        collapsedLabel.isHidden = !content.isCollapsed || content.hiddenReplies == 0
        collapsedLabel.text = "+\(content.hiddenReplies)"
        stack.alpha = content.isCollapsed ? 0.6 : 1

        isAccessibilityElement = true
        accessibilityLabel = "\(author)\(content.isOP ? ", original poster" : ""), \(timeLabel.text ?? "") ago"
        accessibilityValue = content.isCollapsed
            ? "Collapsed, \(content.hiddenReplies) replies hidden"
            : content.body.plainText
    }

    var onLinkTap: ((URL) -> Void)? {
        get { bodyView.onLinkTap }
        set { bodyView.onLinkTap = newValue }
    }

    func updateTime() {
        timeLabel.text = time.map { RelativeTime.string(from: $0) }
    }

    override func updateConfiguration(using state: UICellConfigurationState) {
        var background = UIBackgroundConfiguration.listCell()
        background.backgroundColor = state.isHighlighted
            ? UIColor.white.withAlphaComponent(0.05)
            : Theme.Color.backgroundDark
        backgroundConfiguration = background
    }
}

/// UILabel with padding around the text, for small badges.
final class PaddedLabel: UILabel {
    var insets = UIEdgeInsets(top: 2, left: 2, bottom: 2, right: 2)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right, height: size.height + insets.top + insets.bottom)
    }
}
