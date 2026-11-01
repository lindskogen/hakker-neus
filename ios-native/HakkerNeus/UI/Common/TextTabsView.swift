import UIKit

/// A tab of a `TextTabsView`.
protocol TextTab: CaseIterable, Equatable, Sendable where AllCases: RandomAccessCollection {
    var title: String { get }
}

/// Text tabs across the full width (Stories / Comments on a user page, the sort order of search
/// results): the selected one white with an accent line under it that slides over when the tab
/// changes, the others dimmed.
final class TextTabsView<Tab: TextTab>: UIView {
    var onSelect: ((Tab) -> Void)?
    var selected: Tab {
        get { current }
        set { setSelected(newValue, animated: false) }
    }

    private var current: Tab = Tab.allCases.first!
    private var buttons: [UIButton] = []
    private let underline = UIView()
    private var underlineConstraints: [NSLayoutConstraint] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        buttons = Tab.allCases.map { tab in
            let button = UIButton(type: .custom, primaryAction: UIAction { [unowned self] _ in
                guard tab != current else { return }
                setSelected(tab, animated: true)
                onSelect?(tab)
            })
            button.setTitle(tab.title, for: .normal)
            button.titleLabel?.font = Theme.Font.medium(size: 16, style: .callout)
            button.titleLabel?.adjustsFontForContentSizeCategory = true
            button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
            return button
        }
        let stack = UIStackView(arrangedSubviews: buttons)
        stack.distribution = .fillEqually
        underline.layer.cornerRadius = 1
        for view in [stack, underline] {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            underline.heightAnchor.constraint(equalToConstant: 2),
            underline.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setSelected(_ tab: Tab, animated: Bool) {
        // configure() sets it again after a tap; leave a running animation alone.
        guard tab != current else { return }
        current = tab
        guard animated else { return update() }
        layoutIfNeeded()
        for (tab, button) in zip(Tab.allCases, buttons) {
            UIView.transition(with: button, duration: 0.25, options: [.transitionCrossDissolve, .allowUserInteraction]) {
                self.style(button, selected: tab == self.current)
            }
        }
        update()
        UIView.animate(withDuration: 0.35, delay: 0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0, options: [.allowUserInteraction, .beginFromCurrentState]) {
            self.layoutIfNeeded()
        }
    }

    private func update() {
        underline.backgroundColor = Theme.Color.accent
        for (tab, button) in zip(Tab.allCases, buttons) {
            style(button, selected: tab == current)
        }
        NSLayoutConstraint.deactivate(underlineConstraints)
        let button = buttons[Array(Tab.allCases).firstIndex(of: current) ?? 0]
        underlineConstraints = [
            underline.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            underline.trailingAnchor.constraint(equalTo: button.trailingAnchor),
        ]
        NSLayoutConstraint.activate(underlineConstraints)
    }

    private func style(_ button: UIButton, selected: Bool) {
        button.setTitleColor(UIColor.white.withAlphaComponent(selected ? 1 : 0.4), for: .normal)
        button.setTitleColor(UIColor.white.withAlphaComponent(0.25), for: .highlighted)
        button.accessibilityTraits = selected ? [.button, .selected] : .button
    }
}
