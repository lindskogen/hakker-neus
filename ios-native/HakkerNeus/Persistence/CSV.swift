import Foundation

/// RFC 4180 CSV: quoted fields may contain commas, doubled quotes and line breaks.
enum CSV {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var iterator = text.unicodeScalars.makeIterator()
        var pending: Unicode.Scalar? = iterator.next()

        func endField() { row.append(field); field = "" }
        func endRow() {
            endField()
            // Skip blank lines (a lone empty field).
            if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
            row = []
        }

        while let scalar = pending {
            pending = iterator.next()
            if inQuotes {
                if scalar == "\"" {
                    if pending == "\"" {
                        field.unicodeScalars.append("\"")
                        pending = iterator.next()
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(scalar)
                }
                continue
            }
            switch scalar {
            case "\"": inQuotes = true
            case ",": endField()
            case "\r":
                if pending == "\n" { pending = iterator.next() }
                endRow()
            case "\n": endRow()
            default: field.unicodeScalars.append(scalar)
            }
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }

    static func format(_ rows: [[String]]) -> String {
        rows.map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// The hacker-feed bookmarks format, used for both import and export:
/// id,title,url,hn_url,domain,type,user,points,comments,posted_at,saved_at,text,image_url
enum BookmarksCSV {
    static let columns = ["id", "title", "url", "hn_url", "domain", "type", "user", "points", "comments", "posted_at", "saved_at", "text", "image_url"]

    struct ImportResult {
        var entries: [SavedStoriesStore.Entry]
        var skipped: Int
    }

    static func read(_ text: String) -> ImportResult {
        var rows = CSV.parse(text)
        guard !rows.isEmpty else { return ImportResult(entries: [], skipped: 0) }
        let header = rows.removeFirst().map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        let index = Dictionary(header.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })

        var entries: [SavedStoriesStore.Entry] = []
        var skipped = 0
        for row in rows {
            func value(_ column: String) -> String? {
                guard let i = index[column], i < row.count else { return nil }
                let value = row[i]
                return value.isEmpty ? nil : value
            }
            guard let id = value("id").flatMap({ Int($0) }), let title = value("title") else {
                skipped += 1
                continue
            }
            let posted = value("posted_at").flatMap(parseDate) ?? Date(timeIntervalSince1970: 0)
            let story = Story(
                id: id,
                title: title,
                author: value("user"),
                url: value("url").flatMap(URL.init(string:)),
                text: value("text"),
                score: value("points").flatMap { Int($0) } ?? 0,
                commentCount: value("comments").flatMap { Int($0) } ?? 0,
                time: posted
            )
            entries.append(.init(story: story, savedAt: value("saved_at").flatMap(parseDate) ?? posted))
        }
        return ImportResult(entries: entries, skipped: skipped)
    }

    static func write(_ entries: [SavedStoriesStore.Entry]) -> String {
        let rows = entries.map { entry -> [String] in
            let story = entry.story
            return [
                String(story.id),
                story.title,
                story.url?.absoluteString ?? "",
                story.hackerNewsURL.absoluteString,
                story.displayDomain ?? "",
                story.url == nil ? "ask" : "link",
                story.author ?? "",
                String(story.score),
                String(story.commentCount),
                postedFormatter.string(from: story.time),
                savedFormatter.string(from: entry.savedAt),
                story.text ?? "",
                "",
            ]
        }
        return CSV.format([columns] + rows)
    }

    // Timestamps are ISO 8601 with an offset; saved_at has microseconds, which
    // ISO8601DateFormatter can't read, so use explicit formats.
    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    private static let postedFormatter = formatter("yyyy-MM-dd'T'HH:mm:ssxxx")
    private static let savedFormatter = formatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSxxx")
    private static let readFormatters = [
        savedFormatter, formatter("yyyy-MM-dd'T'HH:mm:ss.SSSxxx"), postedFormatter,
        formatter("yyyy-MM-dd'T'HH:mm:ss.SSSSSSX"), formatter("yyyy-MM-dd'T'HH:mm:ss.SSSX"), formatter("yyyy-MM-dd'T'HH:mm:ssX"),
    ]

    static func parseDate(_ string: String) -> Date? {
        for formatter in readFormatters {
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}
