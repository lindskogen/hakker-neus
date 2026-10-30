import UIKit

/// A small capsule near the top of the screen saying the content shown is an offline copy.
final class OfflineBanner: UIView {
    private let label = PaddedLabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        alpha = 0

        label.insets = UIEdgeInsets(top: 6, left: 12, bottom: 6, right: 12)
        label.font = Theme.Font.medium(size: 13)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .white
        label.backgroundColor = UIColor(white: 0.12, alpha: 0.92)
        label.layer.cornerRadius = 14
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.topAnchor.constraint(equalTo: topAnchor),
            label.bottomAnchor.constraint(equalTo: bottomAnchor),
            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        isAccessibilityElement = true
        accessibilityTraits = .staticText
        accessibilityIdentifier = "offline.banner"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Adds the banner centred under the status bar of `view`.
    func install(in view: UIView) {
        translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(self)
        NSLayoutConstraint.activate([
            centerXAnchor.constraint(equalTo: view.centerXAnchor),
            topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 6),
            leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: Theme.padding * 2),
        ])
    }

    /// Shows the message; with `hideAfter`, fades out again on its own.
    func show(_ message: String, hideAfter: TimeInterval? = nil) {
        label.text = message
        accessibilityLabel = message
        UIView.animate(withDuration: 0.25) { self.alpha = 1 }
        UIAccessibility.post(notification: .announcement, argument: message)
        if let hideAfter {
            UIView.animate(withDuration: 0.4, delay: hideAfter, options: [.beginFromCurrentState]) { self.alpha = 0 }
        }
    }

    func hide() {
        UIView.animate(withDuration: 0.25, delay: 0, options: [.beginFromCurrentState]) { self.alpha = 0 }
    }
}
