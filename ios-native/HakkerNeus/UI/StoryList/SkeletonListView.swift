import UIKit

/// Placeholder rows shown while the front page loads: the same orange ramp as the real rows,
/// with faint bars where the title and domain will be, and a highlight sweeping across.
final class SkeletonListView: UIView {
    private let shimmer = CAGradientLayer()
    private let stack = UIStackView()
    private var stackTop: NSLayoutConstraint!

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.backgroundDark
        isAccessibilityElement = true
        accessibilityLabel = "Loading stories"
        accessibilityTraits = .updatesFrequently

        stack.axis = .vertical
        stack.spacing = 1 / max(traitCollection.displayScale, 1)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        // A collection view's background view gets no safe area, so start below the status bar by hand.
        stackTop = stack.topAnchor.constraint(equalTo: topAnchor)
        NSLayoutConstraint.activate([
            stackTop,
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
        // Enough rows to fill any screen; the rest is clipped.
        for index in 0..<10 {
            stack.addArrangedSubview(Self.row(index: index))
        }
        clipsToBounds = true

        shimmer.colors = [UIColor.clear.cgColor, UIColor.white.withAlphaComponent(0.12).cgColor, UIColor.clear.cgColor]
        shimmer.startPoint = CGPoint(x: 0, y: 0.4)
        shimmer.endPoint = CGPoint(x: 1, y: 0.6)
        shimmer.locations = [0, 0.5, 1]
        layer.addSublayer(shimmer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func row(index: Int) -> UIView {
        let row = UIView()
        row.backgroundColor = Palette.storyBackground(at: index)

        // Two title lines of slightly varying length, then the domain.
        let widths: [CGFloat] = [0.85, 0.55 + CGFloat(index % 3) * 0.1]
        let bars = [bar(height: 20), bar(height: 20), bar(height: 10)]

        let column = UIStackView(arrangedSubviews: bars)
        column.axis = .vertical
        column.alignment = .leading
        column.spacing = 8
        column.setCustomSpacing(12, after: bars[1])
        column.translatesAutoresizingMaskIntoConstraints = false
        row.addSubview(column)

        let padding = Theme.padding
        NSLayoutConstraint.activate([
            row.heightAnchor.constraint(equalToConstant: 100),
            column.topAnchor.constraint(equalTo: row.topAnchor, constant: padding * 2),
            column.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: padding),
            bars[0].widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: widths[0]),
            bars[1].widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: widths[1]),
            bars[2].widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: 0.3),
        ])
        return row
    }

    private static func bar(height: CGFloat) -> UIView {
        let bar = UIView()
        bar.backgroundColor = UIColor.white.withAlphaComponent(0.22)
        bar.layer.cornerRadius = height / 3
        bar.heightAnchor.constraint(equalToConstant: height).isActive = true
        return bar
    }

    override func layoutSubviews() {
        stackTop.constant = window?.safeAreaInsets.top ?? 0
        super.layoutSubviews()
        // Three widths wide, so the highlight can travel across from off-screen to off-screen.
        shimmer.frame = CGRect(x: -bounds.width, y: 0, width: bounds.width * 3, height: bounds.height)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        shimmer.removeAllAnimations()
        guard window != nil, !UIAccessibility.isReduceMotionEnabled else { return }
        let sweep = CABasicAnimation(keyPath: "transform.translation.x")
        sweep.fromValue = -bounds.width
        sweep.toValue = bounds.width
        sweep.duration = 1.4
        sweep.repeatCount = .infinity
        sweep.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        shimmer.add(sweep, forKey: "sweep")
    }
}
