import Foundation

/// Finds Markdown pipe tables in a parsed comment, GitHub style:
///
///     | Name  | Size |
///     | :---- | ---: |
///     | Alpha |   12 |
///
/// A header row, then a delimiter row with the same number of cells (`---`, with `:` for
/// alignment), then body rows until the first line without a `|`. Leading and trailing pipes
/// are optional and `\|` is a literal pipe. HN shows single newlines as spaces, so people often
/// put a blank line between rows: rows split over paragraphs count as one table. A code block
/// that holds nothing but a table becomes a table too.
enum MarkdownTables {
    typealias Run = CommentBody.Run
    typealias Table = CommentBody.Table

    /// Replaces tables in `blocks` with `.table` blocks, and turns the newlines left in
    /// paragraphs into spaces.
    static func extract(from blocks: [CommentBody.Block]) -> [CommentBody.Block] {
        var result: [CommentBody.Block] = []
        // Lines of the paragraphs since the last code block, with the paragraph each came from.
        var lines: [Line] = []
        var paragraph = 0

        func flushLines() {
            result += scan(lines)
            lines = []
        }

        for block in blocks {
            switch block {
            case .paragraph(let runs):
                lines += split(runs).map { Line(paragraph: paragraph, runs: $0) }
                paragraph += 1
            case .code(let code):
                flushLines()
                result.append(table(inCode: code).map(CommentBody.Block.table) ?? block)
            case .table:
                flushLines()
                result.append(block)
            }
        }
        flushLines()
        return result
    }

    // MARK: Finding tables

    private struct Line {
        var paragraph: Int
        var runs: [Run]
        var text: String { runs.map(\.text).joined() }
    }

    private static func scan(_ lines: [Line]) -> [CommentBody.Block] {
        var blocks: [CommentBody.Block] = []
        var prose: [Line] = []
        let runs = lines.map(\.runs)
        var index = 0
        while index < lines.count {
            if case let (found, count)? = table(at: index, in: runs) {
                blocks += paragraphs(prose)
                prose = []
                blocks.append(.table(found))
                index += count
            } else {
                prose.append(lines[index])
                index += 1
            }
        }
        return blocks + paragraphs(prose)
    }

    /// A code block is a table only if every line of it belongs to the table.
    private static func table(inCode code: String) -> Table? {
        let lines = code.split(separator: "\n", omittingEmptySubsequences: false).map { [Run(text: String($0))] }
        guard case let (found, count)? = table(at: 0, in: lines), count == lines.count else { return nil }
        return found
    }

    /// The table whose header row is `lines[start]`, and how many lines it takes up.
    private static func table(at start: Int, in lines: [[Run]]) -> (Table, Int)? {
        guard start + 1 < lines.count,
              hasPipe(lines[start]), hasPipe(lines[start + 1]),
              let alignments = alignments(lines[start + 1])
        else { return nil }
        let header = cells(lines[start])
        guard header.count == alignments.count else { return nil }

        var rows: [[[Run]]] = []
        var end = start + 2
        while end < lines.count, hasPipe(lines[end]) {
            // Like GitHub: short rows are padded with empty cells, extra cells dropped.
            var row = Array(cells(lines[end]).prefix(header.count))
            row += Array(repeating: [], count: header.count - row.count)
            rows.append(row)
            end += 1
        }
        return (Table(alignments: alignments, header: header, rows: rows), end - start)
    }

    /// The alignment of each column if `line` is a delimiter row such as `| :--- | ---: |`.
    private static func alignments(_ line: [Run]) -> [Table.Alignment]? {
        let cells = cells(line).map { $0.map(\.text).joined() }
        guard !cells.isEmpty else { return nil }
        var alignments: [Table.Alignment] = []
        for cell in cells {
            let dashes = cell.drop { $0 == ":" }.reversed().drop { $0 == ":" }
            guard !dashes.isEmpty, dashes.allSatisfy({ $0 == "-" }),
                  cell.prefix(while: { $0 == ":" }).count <= 1,
                  cell.reversed().prefix(while: { $0 == ":" }).count <= 1
            else { return nil }
            switch (cell.hasPrefix(":"), cell.hasSuffix(":")) {
            case (true, true): alignments.append(.center)
            case (false, true): alignments.append(.trailing)
            default: alignments.append(.leading)
            }
        }
        return alignments
    }

    // MARK: Splitting

    /// Splits runs at newlines into lines of runs.
    private static func split(_ runs: [Run]) -> [[Run]] {
        var lines: [[Run]] = [[]]
        for run in runs {
            for (index, part) in run.text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                if index > 0 { lines.append([]) }
                if !part.isEmpty {
                    var piece = run
                    piece.text = String(part)
                    lines[lines.count - 1].append(piece)
                }
            }
        }
        return lines
    }

    private static func hasPipe(_ line: [Run]) -> Bool {
        var escaped = false
        for character in line.map(\.text).joined() {
            if character == "|", !escaped { return true }
            escaped = character == "\\" && !escaped
        }
        return false
    }

    /// The trimmed cells of a row, keeping each cell's italics and links.
    private static func cells(_ line: [Run]) -> [[Run]] {
        var cells: [[Run]] = [[]]
        for run in line {
            var text = ""
            var characters = run.text[...]
            while let character = characters.popFirst() {
                if character == "\\", characters.first == "|" {
                    text.append(characters.removeFirst())
                } else if character == "|" {
                    if !text.isEmpty { cells[cells.count - 1].append(Run(text: text, isItalic: run.isItalic, link: run.link)) }
                    cells.append([])
                    text = ""
                } else {
                    text.append(character)
                }
            }
            if !text.isEmpty { cells[cells.count - 1].append(Run(text: text, isItalic: run.isItalic, link: run.link)) }
        }

        let row = line.map(\.text).joined().trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { cells.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|"), !cells.isEmpty { cells.removeLast() }
        return cells.map(trimmed)
    }

    // MARK: Paragraphs

    /// Joins the lines that aren't part of a table back into their paragraphs.
    private static func paragraphs(_ lines: [Line]) -> [CommentBody.Block] {
        var blocks: [CommentBody.Block] = []
        var index = 0
        while index < lines.count {
            var runs: [Run] = []
            let paragraph = lines[index].paragraph
            while index < lines.count, lines[index].paragraph == paragraph {
                if !runs.isEmpty { runs.append(Run(text: " ")) }
                runs += lines[index].runs
                index += 1
            }
            let kept = trimmed(runs)
            if !kept.isEmpty { blocks.append(.paragraph(kept)) }
        }
        return blocks
    }

    /// Merges neighbouring runs that look the same and trims whitespace from both ends.
    private static func trimmed(_ runs: [Run]) -> [Run] {
        var merged: [Run] = []
        for run in runs where !run.text.isEmpty {
            if let last = merged.last, last.isItalic == run.isItalic, last.link == run.link {
                merged[merged.count - 1].text += run.text
            } else {
                merged.append(run)
            }
        }
        guard !merged.isEmpty else { return [] }
        merged[0].text = String(merged[0].text.drop { $0.isWhitespace })
        merged[merged.count - 1].text = String(merged[merged.count - 1].text.reversed().drop { $0.isWhitespace }.reversed())
        return merged.filter { !$0.text.isEmpty }
    }
}

extension CommentBody.Table {
    /// The table as Markdown with its columns lined up, for copying.
    var markdown: String {
        let text = ([header] + rows).map { row in
            row.map { $0.map(\.text).joined().replacingOccurrences(of: "|", with: "\\|") }
        }
        let widths = alignments.indices.map { column in
            max(3, text.map { $0[column].count }.max() ?? 0)
        }

        func line(_ cells: [String]) -> String {
            "| " + cells.joined(separator: " | ") + " |"
        }
        func padded(_ cell: String, _ column: Int) -> String {
            let space = widths[column] - cell.count
            switch alignments[column] {
            case .leading: return cell + String(repeating: " ", count: space)
            case .trailing: return String(repeating: " ", count: space) + cell
            case .center: return String(repeating: " ", count: space / 2) + cell + String(repeating: " ", count: space - space / 2)
            }
        }

        let delimiter = alignments.enumerated().map { column, alignment in
            switch alignment {
            case .leading: String(repeating: "-", count: widths[column])
            case .trailing: String(repeating: "-", count: widths[column] - 1) + ":"
            case .center: ":" + String(repeating: "-", count: widths[column] - 2) + ":"
            }
        }
        return ([line(text[0].enumerated().map { padded($1, $0) }), line(delimiter)]
            + text.dropFirst().map { row in line(row.enumerated().map { padded($1, $0) }) })
            .joined(separator: "\n")
    }
}
