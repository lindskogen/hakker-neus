import Foundation

enum HTMLText {
    /// Interim plain-text rendering of HN comment HTML: paragraphs become blank lines,
    /// tags are dropped and entities decoded. Replaced by attributed rendering in phase 4.
    static func plainText(fromHTML html: String) -> String {
        let paragraphs = html.replacingOccurrences(of: "<p>", with: "\n\n")
        let stripped = paragraphs.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return decodeEntities(stripped).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decodes named entities HN emits plus all numeric (`&#39;`, `&#x27;`) entities.
    static func decodeEntities(_ string: String) -> String {
        guard string.contains("&") else { return string }

        var result = ""
        result.reserveCapacity(string.count)
        var rest = string[...]

        while let ampersand = rest.firstIndex(of: "&") {
            result += rest[..<ampersand]
            rest = rest[ampersand...]

            // Entities are short; don't scan arbitrarily far for a semicolon.
            guard let semicolon = rest.prefix(10).firstIndex(of: ";"),
                  let decoded = decodeEntity(rest[rest.index(after: ampersand)..<semicolon])
            else {
                result += "&"
                rest = rest.dropFirst()
                continue
            }
            result += decoded
            rest = rest[rest.index(after: semicolon)...]
        }
        return result + rest
    }

    private static func decodeEntity(_ name: Substring) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value = digits.first == "x" || digits.first == "X"
                ? UInt32(digits.dropFirst(), radix: 16)
                : UInt32(digits)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
        return namedEntities[String(name)]
    }

    private static let namedEntities = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
    ]
}
