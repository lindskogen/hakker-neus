import Foundation

/// A parsed HN comment: paragraphs of styled text and preformatted code blocks.
/// Pure value type so it can be built off the main thread and unit tested.
struct CommentBody: Hashable, Sendable {
    enum Block: Hashable, Sendable {
        case paragraph([Run])
        case code(String)
    }

    struct Run: Hashable, Sendable {
        var text: String
        var isItalic = false
        var link: URL?
    }

    var blocks: [Block]

    /// Text for copying: paragraphs separated by blank lines.
    var plainText: String {
        blocks.map { block in
            switch block {
            case .paragraph(let runs): runs.map(\.text).joined()
            case .code(let code): code
            }
        }
        .joined(separator: "\n\n")
    }
}

extension CommentBody {
    /// Parses the HTML subset HN emits: `<p>`, `<i>`, `<a href>`, `<pre><code>` and entities.
    /// Paragraphs are separated by bare `<p>` tags; unknown tags are dropped but their text kept.
    init(html: String) {
        var parser = Parser()
        var rest = html[...]

        while !rest.isEmpty {
            guard let open = rest.firstIndex(of: "<") else {
                parser.text(rest)
                break
            }
            if open > rest.startIndex {
                parser.text(rest[..<open])
            }
            guard let close = rest[open...].firstIndex(of: ">") else {
                // A stray "<" with no closing ">" is just text.
                parser.text(rest[open...])
                break
            }
            parser.tag(rest[rest.index(after: open)..<close])
            rest = rest[rest.index(after: close)...]
        }

        self.blocks = parser.finish()
    }
}

private struct Parser {
    private var blocks: [CommentBody.Block] = []
    private var runs: [CommentBody.Run] = []
    private var italicDepth = 0
    private var link: URL?
    private var code: String?

    mutating func text(_ raw: Substring) {
        let decoded = HTMLText.decodeEntities(String(raw))
        if code != nil {
            code! += decoded
            return
        }
        // Outside <pre>, newlines are whitespace, as in a browser.
        let text = decoded.replacingOccurrences(of: "\n", with: " ")
        let run = CommentBody.Run(text: text, isItalic: italicDepth > 0, link: link)
        if let last = runs.last, last.isItalic == run.isItalic, last.link == run.link {
            runs[runs.count - 1].text += text
        } else {
            runs.append(run)
        }
    }

    mutating func tag(_ raw: Substring) {
        let isClosing = raw.hasPrefix("/")
        let body = isClosing ? raw.dropFirst() : raw
        let name = body.prefix { $0.isLetter || $0.isNumber }.lowercased()

        switch (name, isClosing) {
        case ("p", false):
            flushParagraph()
        case ("pre", false):
            flushParagraph()
            code = ""
        case ("pre", true):
            flushCode()
        case ("i", false), ("em", false):
            italicDepth += 1
        case ("i", true), ("em", true):
            italicDepth = max(0, italicDepth - 1)
        case ("a", false):
            link = Self.href(in: body)
        case ("a", true):
            link = nil
        default:
            // </p>, <code>, </code> and anything unknown carry no meaning of their own.
            break
        }
    }

    mutating func finish() -> [CommentBody.Block] {
        flushCode()
        flushParagraph()
        return blocks
    }

    private mutating func flushParagraph() {
        guard code == nil else { return }
        defer { runs = [] }

        var runs = runs.filter { !$0.text.isEmpty }
        guard !runs.isEmpty else { return }
        runs[0].text = String(runs[0].text.drop { $0.isWhitespace })
        runs[runs.count - 1].text = String(runs[runs.count - 1].text.reversed().drop { $0.isWhitespace }.reversed())
        runs.removeAll { $0.text.isEmpty }

        if !runs.isEmpty {
            blocks.append(.paragraph(runs))
        }
    }

    private mutating func flushCode() {
        guard let code else { return }
        self.code = nil

        // HN keeps the 4-space indent that marks a code block in its input; drop it.
        var lines = code.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.hasPrefix("    ") ? String(line.dropFirst(4)) : String(line)
        }
        while let last = lines.last, last.allSatisfy(\.isWhitespace) { lines.removeLast() }
        while let first = lines.first, first.allSatisfy(\.isWhitespace) { lines.removeFirst() }

        if !lines.isEmpty {
            blocks.append(.code(lines.joined(separator: "\n")))
        }
    }

    private static func href(in tag: Substring) -> URL? {
        guard let range = tag.range(of: #"href\s*=\s*"([^"]*)""#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let attribute = tag[range]
        guard let start = attribute.firstIndex(of: "\""), let end = attribute.lastIndex(of: "\""), start < end else {
            return nil
        }
        let value = HTMLText.decodeEntities(String(attribute[attribute.index(after: start)..<end]))
        return URL(string: value)
    }
}
