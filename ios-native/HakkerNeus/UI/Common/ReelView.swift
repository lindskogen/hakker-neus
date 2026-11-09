import UIKit

/// A place in the reel: a feed, the saved list, search, or something to do to the feed.
struct ReelItem {
    let title: String
    /// The thin bar beside the title: the place's own colour.
    let color: UIColor
    /// Marked "here": the place showing now.
    var isCurrent = false
    /// Goes there. `point` is where the finger let go, in window coordinates.
    let action: (_ point: CGPoint) -> Void
}

/// One site's places, nearest the corner button first.
struct ReelColumn {
    let title: String
    /// The site's colour: the hint at the edge, and darkened, the backdrop.
    let color: UIColor
    let items: [ReelItem]
}

/// The slot machine on the corner button: drag up from the button and the places roll past above
/// the thumb in big type, the one level with it largest; let go to go there. Dragging sideways,
/// toward the middle of the screen, swaps in the other site's places.
///
/// Lives only while the finger is down; `NavigationController` feeds it the finger's position.
final class ReelView: UIView {
    static let step: CGFloat = 62
    /// How far sideways the finger goes to swap in the other site, and to swap back.
    private static let swapDistance: CGFloat = 60
    private static let swapBackDistance: CGFloat = 30

    private let columns: [ReelColumn]
    private let anchor: CGRect
    private let onLeft: Bool
    private let start: CGPoint

    private(set) var column = 0
    private(set) var selection: Int?
    var selectedItem: ReelItem? { selection.map { columns[column].items[$0] } }

    private let backdrop = UIView()
    private var columnViews: [UIView] = []
    private var rows: [[UIView]] = []
    private let hint = UIView()
    private let hintLabel = UILabel()
    private let feedback = UISelectionFeedbackGenerator()

    /// - Parameters:
    ///   - anchor: The corner button's frame, in this view's coordinates.
    ///   - start: Where the finger came down.
    init(frame: CGRect, columns: [ReelColumn], anchor: CGRect, onLeft: Bool, start: CGPoint) {
        self.columns = columns
        self.anchor = anchor
        self.onLeft = onLeft
        self.start = start
        super.init(frame: frame)
        accessibilityElementsHidden = true // VoiceOver gets the places as actions on the button.
        autoresizingMask = [.flexibleWidth, .flexibleHeight]

        backdrop.frame = bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        backdrop.backgroundColor = Self.backdropColor(columns[0].color)
        addSubview(backdrop)

        for (index, column) in columns.enumerated() {
            let view = UIView(frame: bounds)
            view.alpha = index == 0 ? 1 : 0
            rows.append(column.items.map { item in
                let row = Self.makeRow(item, onLeft: onLeft)
                view.addSubview(row)
                return row
            })
            view.addSubview(makeTitle(column.title, count: column.items.count, shift: shift(for: index)))
            addSubview(view)
            columnViews.append(view)
        }
        layoutRows()

        hint.layer.cornerRadius = 9
        hint.layer.maskedCorners = onLeft ? [.layerMinXMinYCorner, .layerMinXMaxYCorner] : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        hintLabel.font = .systemFont(ofSize: 9, weight: .semibold)
        hintLabel.textColor = .white
        hintLabel.transform = CGAffineTransform(rotationAngle: -.pi / 2)
        hint.addSubview(hintLabel)
        hint.isHidden = columns.count < 2
        addSubview(hint)
        placeHint(animated: false)

        feedback.prepare()
        applySelection(animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: Building

    private static func backdropColor(_ color: UIColor) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: nil)
        return UIColor(red: r * 0.2, green: g * 0.2, blue: b * 0.2, alpha: 0.95)
    }

    private static let titleFont = UIFont(name: "HelveticaNeue-Light", size: 36) ?? .systemFont(ofSize: 36, weight: .light)

    /// Bar, title and "here", reading away from the button; scaled about the end nearest it.
    private static func makeRow(_ item: ReelItem, onLeft: Bool) -> UIView {
        let bar = UIView()
        bar.backgroundColor = item.color
        bar.layer.cornerRadius = 2

        let title = UILabel()
        title.text = item.title
        title.font = titleFont
        title.textColor = .white
        title.sizeToFit()

        let tag = UILabel()
        tag.attributedText = NSAttributedString(string: "HERE", attributes: [
            .font: UIFont.systemFont(ofSize: 10, weight: .semibold), .kern: 1.2, .foregroundColor: UIColor.white.withAlphaComponent(0.75),
        ])
        tag.sizeToFit()
        tag.isHidden = !item.isCurrent

        let gap: CGFloat = 12
        let height = title.bounds.height
        let tagWidth = item.isCurrent ? tag.bounds.width + gap : 0
        let width = 4 + gap + title.bounds.width + tagWidth
        let row = UIView(frame: CGRect(x: 0, y: 0, width: width, height: height))
        if onLeft {
            bar.frame = CGRect(x: 0, y: (height - 30) / 2, width: 4, height: 30)
            title.frame.origin = CGPoint(x: 4 + gap, y: 0)
            tag.frame.origin = CGPoint(x: title.frame.maxX + gap, y: (height - tag.bounds.height) / 2 + 2)
        } else {
            tag.frame.origin = CGPoint(x: 0, y: (height - tag.bounds.height) / 2 + 2)
            title.frame.origin = CGPoint(x: tagWidth, y: 0)
            bar.frame = CGRect(x: width - 4, y: (height - 30) / 2, width: 4, height: 30)
        }
        [bar, title, tag].forEach(row.addSubview)
        row.layer.anchorPoint = CGPoint(x: onLeft ? 0 : 1, y: 0.5)
        return row
    }

    /// The site's name, small, above its places.
    private func makeTitle(_ text: String, count: Int, shift: CGFloat) -> UILabel {
        let label = UILabel()
        label.attributedText = NSAttributedString(string: text.uppercased(), attributes: [
            .font: UIFont.systemFont(ofSize: 11, weight: .semibold), .kern: 1.6, .foregroundColor: UIColor.white.withAlphaComponent(0.6),
        ])
        label.sizeToFit()
        let y = anchor.midY - (CGFloat(count) + 0.85) * Self.step
        label.frame.origin = CGPoint(x: onLeft ? edgeX + shift : edgeX - shift - label.bounds.width, y: y)
        return label
    }

    /// Where rows start: just past the button, clear of the thumb dragging up from it.
    private var edgeX: CGFloat { onLeft ? anchor.maxX + 10 : anchor.minX - 10 }

    /// The other site's places sit further in, where the finger went to get them.
    private func shift(for column: Int) -> CGFloat { column == 0 ? 0 : 56 }

    private func layoutRows() {
        for (c, columnRows) in rows.enumerated() {
            let x = onLeft ? edgeX + shift(for: c) : edgeX - shift(for: c)
            for (i, row) in columnRows.enumerated() {
                row.center = CGPoint(x: x, y: anchor.midY - CGFloat(i + 1) * Self.step)
            }
        }
    }

    /// The other site's colour and name at an edge: the far edge to swap to it, the near one to swap back.
    private func placeHint(animated: Bool) {
        guard columns.count > 1 else { return }
        let other = columns[1 - column]
        let height: CGFloat = 150
        let far = column == 0
        let atRight = onLeft == far
        let change = { [self] in
            hint.backgroundColor = other.color
            hint.layer.maskedCorners = atRight
                ? [.layerMinXMinYCorner, .layerMinXMaxYCorner]
                : [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
            hint.frame = CGRect(x: atRight ? bounds.width - 18 : 0, y: anchor.midY - 2.5 * Self.step - height / 2, width: 18, height: height)
            hintLabel.attributedText = NSAttributedString(string: other.title.uppercased(), attributes: [.kern: 1.4])
            hintLabel.bounds.size = hintLabel.intrinsicContentSize
            hintLabel.center = CGPoint(x: 9, y: height / 2)
        }
        animated ? UIView.animate(withDuration: 0.2, animations: change) : change()
    }

    // MARK: Showing

    func show() {
        alpha = 0
        for (i, row) in rows[0].enumerated() {
            row.transform = row.transform.translatedBy(x: 0, y: CGFloat(i + 1) * 14)
        }
        UIView.animate(withDuration: 0.16) { self.alpha = 1 }
        applySelection(animated: true)
    }

    func dismiss(animated: Bool) {
        guard animated else { return removeFromSuperview() }
        UIView.animate(withDuration: 0.2) { self.alpha = 0 } completion: { _ in self.removeFromSuperview() }
    }

    // MARK: Tracking

    func track(_ point: CGPoint) {
        if columns.count > 1 {
            let sideways = (point.x - start.x) * (onLeft ? 1 : -1)
            if column == 0, sideways > Self.swapDistance {
                setColumn(1)
            } else if column == 1, sideways < Self.swapBackDistance {
                setColumn(0)
            }
        }

        // Each place owns a band a step tall, centred on it; below the first, nothing.
        let rise = anchor.midY - point.y
        let count = columns[column].items.count
        let band = Int((rise / Self.step - 0.5).rounded(.down))
        let new: Int? = band < 0 || count == 0 ? nil : min(band, count - 1)
        guard new != selection else { return }
        selection = new
        feedback.selectionChanged()
        feedback.prepare()
        applySelection(animated: true)
    }

    private func setColumn(_ new: Int) {
        let old = column
        column = new
        selection = nil
        feedback.selectionChanged()
        let slide: CGFloat = (onLeft ? 1 : -1) * (new > old ? -30 : 30)
        columnViews[new].transform = CGAffineTransform(translationX: -slide, y: 0)
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) { [self] in
            columnViews[old].alpha = 0
            columnViews[old].transform = CGAffineTransform(translationX: slide, y: 0)
            columnViews[new].alpha = 1
            columnViews[new].transform = .identity
            backdrop.backgroundColor = Self.backdropColor(columns[new].color)
        }
        placeHint(animated: true)
    }

    /// The selected place full size; the others smaller and fainter the further they are from it.
    private func applySelection(animated: Bool) {
        let change = { [self] in
            for (i, row) in rows[column].enumerated() {
                let distance = selection.map { abs($0 - i) } ?? (i + 1)
                let selected = distance == 0
                let scale = selected ? 1 : max(0.42, 0.64 - 0.06 * CGFloat(distance))
                row.transform = CGAffineTransform(scaleX: scale, y: scale)
                row.alpha = selected ? 1 : max(0.28, 0.62 - 0.1 * CGFloat(distance))
            }
        }
        if animated, !UIAccessibility.isReduceMotionEnabled {
            UIView.animate(withDuration: 0.22, delay: 0, usingSpringWithDamping: 0.8, initialSpringVelocity: 0, options: [.beginFromCurrentState, .allowUserInteraction], animations: change)
        } else {
            change()
        }
    }
}
