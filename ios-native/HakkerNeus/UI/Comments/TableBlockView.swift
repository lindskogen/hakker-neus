import UIKit

/// A Markdown table: a grid with a bold header row, hairline rules and the code block's
/// border. It scrolls sideways when it's wider than the comment, or, with Wrap Code Lines and
/// Tables on in Settings, fits the comment's width and wraps its cells. Cells keep italics and links.
final class TableBlockView: UIView {
    var onLinkTap: ((URL) -> Void)?
    var linkMenu: ((URL, UIView) -> UIMenu?)?

    init(table: CommentBody.Table, style: CommentTextStyle = .current) {
        super.init(frame: .zero)

        let hairline = 1 / max(traitCollection.displayScale, 1)
        layer.borderWidth = hairline
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor

        let texts = ([table.header] + table.rows).enumerated().map { index, row in
            row.map { Self.attributedString(for: $0, isHeader: index == 0, style: style) }
        }
        let rows = texts.map { row in
            row.map { text in
                let cell = LinkTextView()
                cell.attributedText = text
                cell.onLinkTap = { [weak self] in self?.onLinkTap?($0) }
                cell.linkMenu = { [weak self] url, source in self?.linkMenu?(url, source) }
                return cell
            }
        }

        let content: UIView
        if style.wrapsLines {
            content = FittedTableView(rows: rows, texts: texts, alignments: table.alignments)
        } else {
            content = ScrollingTableView(rows: rows.map { $0.map { $0 as UIView } }, alignments: table.alignments)
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor),
            content.bottomAnchor.constraint(equalTo: bottomAnchor),
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
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

/// The table at its natural width in a scroll view, spread out when narrower than the comment.
private final class ScrollingTableView: UIView {
    init(rows: [[UIView]], alignments: [CommentBody.Table.Alignment]) {
        super.init(frame: .zero)
        let scrollView = UIScrollView()
        let grid = TableGridView(rows: rows, alignments: alignments)
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
}

/// Lays out table cells in columns as wide as their widest cell (up to a cap, past which
/// cells wrap) and rows as tall as their tallest, and draws the rules between them.
private final class TableGridView: UIView {
    private let rows: [[UIView]]
    private let alignments: [CommentBody.Table.Alignment]
    private let rules = CAShapeLayer()
    private let headerBackground = CALayer()
    private var measured: (cells: [[CGSize]], columns: [CGFloat], rows: [CGFloat])?

    static let horizontalPadding = Theme.padding
    static let verticalPadding = Theme.padding / 2
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

/// The table fitted to the comment's width, its cells wrapping. Like a browser: every column
/// gets at least its longest word, and the room left goes to the columns with the most text.
/// Comments are self-sized with Auto Layout, so the columns are fractions of the table's width,
/// worked out for a typical phone-width comment, and Auto Layout wraps the cells to fit.
private final class FittedTableView: UIStackView {
    private static let typicalWidth: CGFloat = 340

    init(rows: [[LinkTextView]], texts: [[NSAttributedString]], alignments: [CommentBody.Table.Alignment]) {
        super.init(frame: .zero)
        axis = .vertical

        let padding = 2 * TableGridView.horizontalPadding
        let natural = alignments.indices.map { column in texts.map { Self.width(of: $0[column]) }.max()! + padding }
        let minimum = alignments.indices.map { column in texts.map { Self.longestWord(in: $0[column]) }.max()! + padding }
        let fractions = Self.fractions(natural: natural, minimum: minimum, width: Self.typicalWidth)
        let hairline = 1 / max(traitCollection.displayScale, 1)
        let ruleColor = UIColor.white.withAlphaComponent(0.25)

        for (index, cells) in rows.enumerated() {
            let row = UIView()
            if index == 0 { row.backgroundColor = UIColor.white.withAlphaComponent(0.08) }
            var constraints: [NSLayoutConstraint] = []
            var previous: NSLayoutXAxisAnchor = row.leadingAnchor

            for (column, cell) in cells.enumerated() {
                let text = NSMutableAttributedString(attributedString: cell.attributedText)
                let paragraph = NSMutableParagraphStyle()
                paragraph.alignment = switch alignments[column] {
                case .leading: .natural
                case .center: .center
                case .trailing: .right
                }
                text.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: text.length))
                cell.attributedText = text

                let box = UIView()
                for view in [box, cell] { view.translatesAutoresizingMaskIntoConstraints = false }
                row.addSubview(box)
                box.addSubview(cell)
                constraints += [
                    box.topAnchor.constraint(equalTo: row.topAnchor),
                    box.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                    box.leadingAnchor.constraint(equalTo: previous),
                    box.widthAnchor.constraint(equalTo: row.widthAnchor, multiplier: fractions[column]),
                    cell.topAnchor.constraint(equalTo: box.topAnchor, constant: TableGridView.verticalPadding),
                    cell.bottomAnchor.constraint(lessThanOrEqualTo: box.bottomAnchor, constant: -TableGridView.verticalPadding),
                    cell.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: TableGridView.horizontalPadding),
                    cell.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -TableGridView.horizontalPadding),
                ]
                if column > 0 {
                    let rule = UIView()
                    rule.backgroundColor = ruleColor
                    rule.translatesAutoresizingMaskIntoConstraints = false
                    box.addSubview(rule)
                    constraints += [
                        rule.topAnchor.constraint(equalTo: box.topAnchor),
                        rule.bottomAnchor.constraint(equalTo: box.bottomAnchor),
                        rule.leadingAnchor.constraint(equalTo: box.leadingAnchor),
                        rule.widthAnchor.constraint(equalToConstant: hairline),
                    ]
                }
                previous = box.trailingAnchor
            }

            // Rows are as tall as their tallest cell.
            let hug = row.heightAnchor.constraint(equalToConstant: 0)
            hug.priority = .fittingSizeLevel
            constraints.append(hug)
            if index < rows.count - 1 {
                let rule = UIView()
                rule.backgroundColor = ruleColor
                rule.translatesAutoresizingMaskIntoConstraints = false
                row.addSubview(rule)
                constraints += [
                    rule.leadingAnchor.constraint(equalTo: row.leadingAnchor),
                    rule.trailingAnchor.constraint(equalTo: row.trailingAnchor),
                    rule.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                    rule.heightAnchor.constraint(equalToConstant: hairline),
                ]
            }
            NSLayoutConstraint.activate(constraints)
            addArrangedSubview(row)
        }
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Each column's share of `width`: its natural width if everything fits, else its longest
    /// word plus a share of the rest in proportion to how much more it would like. Same as Android.
    static func fractions(natural: [CGFloat], minimum: [CGFloat], width: CGFloat) -> [CGFloat] {
        let total = natural.reduce(0, +)
        let least = minimum.reduce(0, +)
        let widths: [CGFloat]
        if total <= width {
            widths = natural
        } else if least >= width {
            // Even the longest words don't fit: those break too.
            widths = minimum
        } else {
            let wanted = zip(natural, minimum).map { max(0, $0 - $1) }
            let share = (width - least) / max(wanted.reduce(0, +), 1)
            widths = zip(minimum, wanted).map { $0 + $1 * share }
        }
        let sum = max(widths.reduce(0, +), 1)
        return widths.map { $0 / sum }
    }

    private static func width(of text: NSAttributedString) -> CGFloat {
        ceil(text.boundingRect(with: CGSize(width: .greatestFiniteMagnitude, height: .greatestFiniteMagnitude), options: [.usesLineFragmentOrigin], context: nil).width)
    }

    /// The widest run of text between spaces, the narrowest a cell can wrap to without breaking words.
    private static func longestWord(in text: NSAttributedString) -> CGFloat {
        let string = text.string as NSString
        var longest: CGFloat = 0
        var start = 0
        for index in 0...string.length {
            guard index == string.length || string.character(at: index) == 0x20 else { continue }
            if index > start {
                longest = max(longest, width(of: text.attributedSubstring(from: NSRange(location: start, length: index - start))))
            }
            start = index + 1
        }
        return longest
    }
}
