import Foundation

/// HN's comment formatting, for showing a just-posted comment before Algolia has it:
/// blank lines separate paragraphs, `*text*` is italic, lines indented by two spaces are
/// code, and bare URLs become links.
enum HNFormatting {
    static func html(fromPlainText text: String) -> String {
        let paragraphs = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: CharacterSet.newlines) }
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        return paragraphs.enumerated().map { index, paragraph in
            let lines = paragraph.components(separatedBy: "\n")
            if lines.allSatisfy({ $0.hasPrefix("  ") }) {
                let code = lines.map { "  " + escape($0) }.joined(separator: "\n")
                return "<pre><code>\(code)</code></pre>"
            }
            let inline = linkify(italicize(escape(lines.joined(separator: " "))))
            return index == 0 ? inline : "<p>" + inline
        }
        .joined()
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    private static func italicize(_ text: String) -> String {
        text.replacingOccurrences(of: #"\*([^*\n]+)\*"#, with: "<i>$1</i>", options: .regularExpression)
    }

    private static func linkify(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"(https?://[^\s<]+[^\s<.,;:!?)\]])"#,
            with: #"<a href="$1">$1</a>"#,
            options: .regularExpression
        )
    }
}
