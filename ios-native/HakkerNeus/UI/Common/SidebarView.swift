import UIKit

/// A place in the sidebar.
struct SidebarItem {
    let title: String
    let systemImage: String
    var isCurrent = false
    /// Runs when the item is picked.
    let action: () -> Void
}

/// A group of places in the sidebar, under a heading in its colour.
struct SidebarSection {
    let title: String?
    let color: UIColor
    let items: [SidebarItem]
}

/// The sidebar: a panel of places behind the screen, uncovered as the screen slides right.
/// It drifts in a little and brightens as it's uncovered, following `progress`, so a swipe can
/// drag it. A line in the accent colour runs down its edge, where the screen meets it.
final class SidebarView: UIView {
    private let panel = UIView()
    private let dimming = UIView()
    private let border = UIView()
    private let scrollView = UIScrollView()
    private let stack = UIStackView()

    /// Called with the picked item.
    var onSelect: ((SidebarItem) -> Void)?
    /// Called when VoiceOver's escape is used.
    var onDismiss: (() -> Void)?

    /// How far open: 0 closed, 1 open. Animatable.
    var progress: CGFloat = 0 {
        didSet {
            let clamped = min(max(progress, 0), 1)
            panel.transform = CGAffineTransform(translationX: -bounds.width * 0.3 * (1 - clamped), y: 0)
            dimming.alpha = 0.6 * (1 - clamped)
        }
    }

    /// How wide the panel is in a screen `width` wide.
    static func width(in width: CGFloat) -> CGFloat { min(width * 0.8, 320) }

    init(frame: CGRect, sections: [SidebarSection], accent: UIColor) {
        super.init(frame: frame)
        autoresizingMask = [.flexibleHeight]
        accessibilityViewIsModal = true
        accessibilityIdentifier = "sidebar"
        clipsToBounds = true
        backgroundColor = Theme.Color.backgroundDark

        panel.frame = bounds
        panel.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        panel.backgroundColor = Theme.Color.backgroundDark
        addSubview(panel)

        dimming.frame = bounds
        dimming.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        dimming.backgroundColor = .black
        dimming.isUserInteractionEnabled = false
        addSubview(dimming)

        border.backgroundColor = accent
        border.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(border)

        scrollView.alwaysBounceVertical = true
        scrollView.indicatorStyle = .white
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(scrollView)

        stack.axis = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        let guide = panel.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: panel.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: border.leadingAnchor),
            border.topAnchor.constraint(equalTo: panel.topAnchor),
            border.bottomAnchor.constraint(equalTo: panel.bottomAnchor),
            border.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            border.widthAnchor.constraint(equalToConstant: 1.5),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: Theme.padding * 2),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -Theme.padding * 2),
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: Theme.padding),
            stack.trailingAnchor.constraint(equalTo: border.leadingAnchor, constant: -Theme.padding),
        ])

        for (index, section) in sections.enumerated() {
            if index > 0 { stack.setCustomSpacing(Theme.padding * 2.5, after: stack.arrangedSubviews.last!) }
            if let title = section.title {
                stack.addArrangedSubview(heading(title, color: section.color))
            }
            for item in section.items {
                stack.addArrangedSubview(row(for: item, color: section.color))
            }
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Stops it mid-animation, for a swipe to take over at `progress`.
    func stopAnimations(at progress: CGFloat) {
        panel.layer.removeAllAnimations()
        dimming.layer.removeAllAnimations()
        self.progress = progress
    }

    override func accessibilityPerformEscape() -> Bool {
        onDismiss?()
        return true
    }

    private func heading(_ title: String, color: UIColor) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = Theme.Font.bold(size: 13, style: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.accessibilityTraits = .header
        let container = UIView()
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: container.topAnchor),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.padding / 2),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: Theme.padding * 1.2),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        return container
    }

    private func row(for item: SidebarItem, color: UIColor) -> UIView {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(systemName: item.systemImage)
        config.preferredSymbolConfigurationForImage = .init(pointSize: 17, weight: .medium)
        config.imagePadding = 14
        config.imageColorTransformer = UIConfigurationColorTransformer { _ in color }
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: Theme.padding * 1.2, bottom: 12, trailing: Theme.padding)
        config.cornerStyle = .large
        let font = item.isCurrent ? Theme.Font.bold(size: 17, style: .body) : Theme.Font.medium(size: 17, style: .body)
        config.attributedTitle = AttributedString(item.title, attributes: AttributeContainer([.font: font]))
        if item.isCurrent {
            config.background.backgroundColor = color.withAlphaComponent(0.22)
        }

        let button = UIButton(configuration: config)
        button.contentHorizontalAlignment = .leading
        button.accessibilityIdentifier = "sidebar.\(item.title)"
        if item.isCurrent { button.accessibilityTraits.insert(.selected) }
        button.addAction(UIAction { [weak self] _ in
            self?.onSelect?(item)
        }, for: .touchUpInside)
        return button
    }
}
