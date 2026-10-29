import UIKit

/// Renders a `CommentBody`: text paragraphs in one link-aware text view per run of paragraphs,
/// and code blocks as horizontally scrolling monospaced views.
final class CommentBodyView: UIStackView {
    /// Called when a link is tapped.
    var onLinkTap: ((URL) -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        axis = .vertical
        spacing = Theme.padding
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(with body: CommentBody) {
        arrangedSubviews.forEach { $0.removeFromSuperview() }

        // Consecutive paragraphs share a text view so selection and layout stay simple.
        var paragraphs: [[CommentBody.Run]] = []
        func flushText() {
            guard !paragraphs.isEmpty else { return }
            let textView = LinkTextView()
            textView.attributedText = Self.attributedString(for: paragraphs)
            textView.onLinkTap = { [weak self] in self?.onLinkTap?($0) }
            addArrangedSubview(textView)
            paragraphs = []
        }

        for block in body.blocks {
            switch block {
            case .paragraph(let runs):
                paragraphs.append(runs)
            case .code(let code):
                flushText()
                addArrangedSubview(CodeBlockView(code: code))
            }
        }
        flushText()
    }

    static func attributedString(for paragraphs: [[CommentBody.Run]]) -> NSAttributedString {
        let font = Theme.Font.body()
        let italic = font.fontDescriptor.withSymbolicTraits(.traitItalic).map { UIFont(descriptor: $0, size: font.pointSize) } ?? font

        let style = NSMutableParagraphStyle()
        style.paragraphSpacing = Theme.padding

        let result = NSMutableAttributedString()
        for (index, runs) in paragraphs.enumerated() {
            if index > 0 { result.append(NSAttributedString(string: "\n")) }
            for run in runs {
                var attributes: [NSAttributedString.Key: Any] = [
                    .font: run.isItalic ? italic : font,
                    .foregroundColor: UIColor.white,
                    .paragraphStyle: style,
                ]
                if let link = run.link {
                    attributes[.link] = link
                }
                result.append(NSAttributedString(string: run.text, attributes: attributes))
            }
        }
        return result
    }
}

/// Non-editable text view that only takes touches on links, so taps elsewhere
/// reach the cell (tap to collapse) and long presses reach the cell's context menu.
final class LinkTextView: UITextView {
    var onLinkTap: ((URL) -> Void)?

    init() {
        // An explicit TextKit 1 stack, because link hit-testing below uses NSLayoutManager.
        let storage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        super.init(frame: .zero, textContainer: container)

        isEditable = false
        isScrollEnabled = false
        isSelectable = true
        scrollsToTop = false
        backgroundColor = .clear
        textContainerInset = .zero
        textContainer.lineFragmentPadding = 0
        linkTextAttributes = [
            .foregroundColor: UIColor.white,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ]
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        guard super.point(inside: point, with: event), attributedText.length > 0 else { return false }

        let location = CGPoint(x: point.x - textContainerInset.left, y: point.y - textContainerInset.top)
        let glyph = layoutManager.glyphIndex(for: location, in: textContainer)
        // glyphIndex returns the nearest glyph, so also check the point is actually on it.
        let glyphRect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: textContainer)
        guard glyphRect.insetBy(dx: -4, dy: -4).contains(location) else { return false }

        let character = layoutManager.characterIndexForGlyph(at: glyph)
        return character < attributedText.length
            && attributedText.attribute(.link, at: character, effectiveRange: nil) != nil
    }
}

extension LinkTextView: UITextViewDelegate {
    func textView(_ textView: UITextView, primaryActionFor textItem: UITextItem, defaultAction: UIAction) -> UIAction? {
        guard case .link(let url) = textItem.content, let onLinkTap else { return defaultAction }
        return UIAction { _ in onLinkTap(url) }
    }
}

/// A `<pre><code>` block: unwrapped Menlo text that scrolls sideways inside a hairline border.
final class CodeBlockView: UIView {
    let scrollView = UIScrollView()

    init(code: String) {
        super.init(frame: .zero)

        layer.borderWidth = 1 / max(traitCollection.displayScale, 1)
        layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor

        let label = UILabel()
        label.text = code
        label.font = Theme.Font.monospaced()
        label.textColor = .white
        label.numberOfLines = 0
        label.lineBreakMode = .byClipping

        scrollView.showsHorizontalScrollIndicator = false
        scrollView.alwaysBounceHorizontal = false
        scrollView.scrollsToTop = false
        scrollView.isAccessibilityElement = true
        scrollView.accessibilityLabel = "Code"
        scrollView.accessibilityValue = code

        for view in [scrollView, label] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(scrollView)
        scrollView.addSubview(label)

        let padding = Theme.padding
        let content = scrollView.contentLayoutGuide
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),

            label.topAnchor.constraint(equalTo: content.topAnchor, constant: padding),
            label.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -padding),
            label.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: padding),
            label.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -padding),

            // Height follows the code; width scrolls.
            scrollView.frameLayoutGuide.heightAnchor.constraint(equalTo: content.heightAnchor),
            content.widthAnchor.constraint(greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}
