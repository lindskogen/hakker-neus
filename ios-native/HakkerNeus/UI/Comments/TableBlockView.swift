import UIKit

/// A Markdown table: a grid with a bold header row, hairline rules and the code block's
/// border, scrolling sideways when it's wider than the comment. Cells keep italics and links.
final class TableBlockView: UIView {
    var onLinkTap: ((URL) -> Void)?
    var linkMenu: ((URL, UIView) -> UIMenu?)?

    private let scrollView = UIScrollView()

    init(table: CommentBody.Table, style: CommentTextStyle = .current) {
        super.init(frame: .zero)

        let hairline = 1 / max(traitCollection.displayScale, 1)
        layer.borderWidth = hairline
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor

        let rows = ([table.header] + table.rows).enumerated().map { index, row in
            row.map { runs in
                let cell = LinkTextView()
                cell.attributedText = Self.attributedString(for: runs, isHeader: index == 0, style: style)
                cell.onLinkTap = { [weak self] in self?.onLinkTap?($0) }
                cell.linkMenu = { [weak self] url, source in self?.linkMenu?(url, source) }
                return cell as UIView
            }
        }
        let grid = TableGridView(rows: rows, alignments: table.alignments)

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.scrollsToTop = false

        for view in [scrollView, grid] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(scrollView)
        scrollView.addSubview(grid)

        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            grid.topAnchor.constraint(equalTo: content.topAnchor),
            grid.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            grid.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: content.trailingAnchor),

            // Height follows the table; it scrolls sideways when wider than the comment,
            // and spreads its columns out when narrower.
            scrollView.frameLayoutGuide.heightAnchor.constraint(equalTo: content.heightAnchor),
            content.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private static func attributedString(for runs: [CommentBody.Run], isHeader: Bool, style: CommentTextStyle) -> NSAttributedString {
        let text = NSMutableAttributedString(attributedString: CommentBodyView.attributedString(for: [runs], style: style))
        guard isHeader, text.length > 0 else { return text }
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            guard let font = value as? UIFont else { return }
            let traits = font.fontDescriptor.symbolicTraits.union(.traitBold)
            if let descriptor = font.fontDescriptor.withSymbolicTraits(traits) {
                text.addAttribute(.font, value: UIFont(descriptor: descriptor, size: font.pointSize), range: range)
            }
        }
        return text
    }
}

/// Lays out table cells in columns as wide as their widest cell (up to a cap, past which
/// cells wrap) and rows as tall as their tallest, and draws the rules between them.
private final class TableGridView: UIView {
    private let rows: [[UIView]]
    private let alignments: [CommentBody.Table.Alignment]
    private let rules = CAShapeLayer()
    private let headerBackground = CALayer()
    private var measured: (cells: [[CGSize]], columns: [CGFloat], rows: [CGFloat])?

    private static let horizontalPadding = Theme.padding
    private static let verticalPadding = Theme.padding / 2
    private static let maximumCellWidth: CGFloat = 260

    init(rows: [[UIView]], alignments: [CommentBody.Table.Alignment]) {
        self.rows = rows
        self.alignments = alignments
        super.init(frame: .zero)

        headerBackground.backgroundColor = UIColor.white.withAlphaComponent(0.08).cgColor
        layer.addSublayer(headerBackground)
        rules.strokeColor = UIColor.white.withAlphaComponent(0.25).cgColor
        rules.fillColor = nil
        layer.addSublayer(rules)
        rows.joined().forEach(addSubview)

        registerForTraitChanges([UITraitPreferredContentSizeCategory.self]) { (self: Self, _: UITraitCollection) in
            self.measured = nil
            self.invalidateIntrinsicContentSize()
            self.setNeedsLayout()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func measure() -> (cells: [[CGSize]], columns: [CGFloat], rows: [CGFloat]) {
        if let measured { return measured }
        let fitting = CGSize(width: Self.maximumCellWidth, height: .greatestFiniteMagnitude)
        let cells = rows.map { row in
            row.map { cell in
                let size = cell.sizeThatFits(fitting)
                return CGSize(width: ceil(min(size.width, Self.maximumCellWidth)), height: ceil(size.height))
            }
        }
        let columns = alignments.indices.map { column in
            (cells.map { $0[column].width }.max() ?? 0) + 2 * Self.horizontalPadding
        }
        let heights = cells.map { row in
            (row.map(\.height).max() ?? 0) + 2 * Self.verticalPadding
        }
        measured = (cells, columns, heights)
        return (cells, columns, heights)
    }

    override var intrinsicContentSize: CGSize {
        let (_, columns, rows) = measure()
        return CGSize(width: columns.reduce(0, +), height: rows.reduce(0, +))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let (cells, natural, heights) = measure()

        // Share out any room beyond the table's natural width evenly between the columns.
        let extra = max(0, bounds.width - natural.reduce(0, +)) / CGFloat(max(natural.count, 1))
        let widths = natural.map { $0 + extra }

        let path = UIBezierPath()
        var y: CGFloat = 0
        for (rowIndex, row) in rows.enumerated() {
            var x: CGFloat = 0
            for (column, cell) in row.enumerated() {
                let size = cells[rowIndex][column]
                let room = widths[column] - 2 * Self.horizontalPadding
                let offset: CGFloat = switch alignments[column] {
                case .leading: 0
                case .center: (room - size.width) / 2
                case .trailing: room - size.width
                }
                cell.frame = CGRect(x: x + Self.horizontalPadding + offset, y: y + Self.verticalPadding, width: size.width, height: size.height)
                if column > 0 {
                    path.move(to: CGPoint(x: x, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + heights[rowIndex]))
                }
                x += widths[column]
            }
            y += heights[rowIndex]
            if rowIndex < rows.count - 1 {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: bounds.width, y: y))
            }
        }

        rules.lineWidth = 1 / max(traitCollection.displayScale, 1)
        rules.frame = bounds
        rules.path = path.cgPath
        headerBackground.frame = CGRect(x: 0, y: 0, width: bounds.width, height: heights.first ?? 0)
    }
}
