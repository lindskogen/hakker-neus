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
///
/// ASCII grid tables, as psql, MySQL and pandoc draw them, count too:
///
///     +-------+------+
///     | Name  | Size |
///     +=======+======+
///     | Alpha |   12 |
///     +-------+------+
///
/// The `+` in the borders mark the columns, so a `|` inside a cell stays text. Rows before
/// the first rule under the top border are the header. When every body row has a rule under
/// it, a row can wrap over several lines, as in pandoc; otherwise each line is a row.
/// Columns take the alignment of `:` in the rule under the header, as in pandoc, or else
/// line up right when every body cell is pushed to the right.
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
            if case let (found, count)? = anyTable(at: index, in: runs) {
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
        guard case let (found, count)? = anyTable(at: 0, in: lines), count == lines.count else { return nil }
        return found
    }

    /// The table starting at `lines[start]`, and how many lines it takes up.
    private static func anyTable(at start: Int, in lines: [[Run]]) -> (Table, Int)? {
        pipeTable(at: start, in: lines) ?? gridTable(at: start, in: lines)
    }

    /// The pipe table whose header row is `lines[start]`, and how many lines it takes up.
    private static func pipeTable(at start: Int, in lines: [[Run]]) -> (Table, Int)? {
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


    // MARK: Grid tables

    /// The grid table whose top border is `lines[start]`, and how many lines it takes up.
    private static func gridTable(at start: Int, in lines: [[Run]]) -> (Table, Int)? {
        let top = Array(text(lines[start]).trimmingCharacters(in: .whitespaces))
        guard isBorder(top) else { return nil }
        // Where the columns' edges are, counted from the first character of the line.
        let edges = top.indices.filter { top[$0] == "+" }
        let columns = edges.count - 1

        // The rows between each pair of rules, and the rules.
        var sections: [[[Run]]] = [[]]
        var rules: [[Character]] = [top]
        var end = start + 1
        while end < lines.count {
            let line = Array(text(lines[end]).trimmingCharacters(in: .whitespaces))
            if isBorder(line) {
                rules.append(line)
                sections.append([])
            } else if line.count >= 2, line.first == "|", line.last == "|" {
                sections[sections.count - 1].append(lines[end])
            } else {
                break
            }
            end += 1
        }
        sections.removeAll { $0.isEmpty }
        guard let first = sections.first else { return nil }

        func row(_ lines: [[Run]]) -> [[Run]] {
            // A row wrapped over several lines joins each cell's lines with spaces.
            let split = lines.map { gridCells($0, edges: edges, columns: columns) }
            return (0..<columns).map { column in
                trimmed(Array(split.map { $0[column] }.joined(separator: [Run(text: " ")])))
            }
        }

        let header: [[Run]]
        let body: [[[Run]]]
        let bodyLines: [[Run]]
        if sections.count == 1 {
            // No rule under a header: the first line is the header.
            header = row([first[0]])
            bodyLines = Array(first.dropFirst())
            body = bodyLines.map { row([$0]) }
        } else {
            header = row(first)
            let rest = sections.dropFirst()
            bodyLines = Array(rest.joined())
            body = rest.count > 1 ? rest.map(row) : bodyLines.map { row([$0]) }
        }

        let separator = rules.dropFirst().first ?? top
        let alignments = ruleAlignments(separator, edges: edges) ?? (0..<columns).map { column in
            inferredAlignment(bodyLines.map { gridCells($0, edges: edges, columns: columns, trimming: false)[column] })
        }
        return (Table(alignments: alignments, header: header, rows: body), end - start)
    }

    /// `+----+====+` or `+:---+---:+`.
    private static func isBorder(_ line: [Character]) -> Bool {
        line.count >= 3 && line.first == "+" && line.last == "+"
            && line.allSatisfy { "+-=:".contains($0) }
            && zip(line, line.dropFirst()).allSatisfy { !($0 == "+" && $1 == "+") }
            && line.contains { $0 == "-" || $0 == "=" }
    }

    /// The cells of a grid row, split at the pipes below the border's `+`, or at every pipe when
    /// the row doesn't line up with the border (wide characters, say).
    private static func gridCells(_ line: [Run], edges: [Int], columns: Int, trimming: Bool = true) -> [[Run]] {
        let characters = Array(text(line))
        let indent = characters.prefix { $0.isWhitespace }.count
        let positions = edges.map { $0 + indent }
        var cells = positions.allSatisfy({ $0 < characters.count && characters[$0] == "|" })
            ? Array(rawCells(line, splittingAt: Set(positions)).dropFirst().dropLast())
            : Array(rawCells(line).dropFirst().dropLast())
        cells = Array(cells.prefix(columns)) + Array(repeating: [], count: max(0, columns - cells.count))
        return trimming ? cells.map(trimmed) : cells
    }

    /// The alignments a rule's colons give, or nil if it has none.
    private static func ruleAlignments(_ rule: [Character], edges: [Int]) -> [Table.Alignment]? {
        guard rule.contains(":"), rule.count > edges.last ?? 0 else { return nil }
        return zip(edges, edges.dropFirst()).map { left, right in
            switch (rule[left + 1] == ":", rule[right - 1] == ":") {
            case (true, true): .center
            case (false, true): .trailing
            default: .leading
            }
        }
    }

    /// Right-aligned when every filled cell has at most one space after it and one has more before.
    private static func inferredAlignment(_ cells: [[Run]]) -> Table.Alignment {
        let filled = cells.map(text).filter { !$0.allSatisfy(\.isWhitespace) }
        let leading = filled.map { $0.prefix { $0 == " " }.count }
        let trailing = filled.map { $0.reversed().prefix { $0 == " " }.count }
        return !filled.isEmpty && trailing.allSatisfy({ $0 <= 1 }) && leading.contains(where: { $0 > 1 }) ? .trailing : .leading
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
        for character in text(line) {
            if character == "|", !escaped { return true }
            escaped = character == "\\" && !escaped
        }
        return false
    }

    private static func text(_ line: [Run]) -> String {
        line.map(\.text).joined()
    }

    /// The trimmed cells of a pipe-table row, keeping each cell's italics and links.
    private static func cells(_ line: [Run]) -> [[Run]] {
        var cells = rawCells(line)
        let row = text(line).trimmingCharacters(in: .whitespaces)
        if row.hasPrefix("|") { cells.removeFirst() }
        if row.hasSuffix("|"), !row.hasSuffix("\\|"), !cells.isEmpty { cells.removeLast() }
        return cells.map(trimmed)
    }

    /// A row split into untrimmed cells at every unescaped pipe, or only at the pipes at
    /// `positions` (character offsets in the line), keeping italics and links.
    private static func rawCells(_ line: [Run], splittingAt positions: Set<Int>? = nil) -> [[Run]] {
        var cells: [[Run]] = [[]]
        var position = 0
        for run in line {
            var text = ""
            func flush() {
                if !text.isEmpty { cells[cells.count - 1].append(Run(text: text, isItalic: run.isItalic, link: run.link)) }
                text = ""
            }
            var characters = run.text[...]
            while let character = characters.popFirst() {
                let index = position
                position += 1
                if let positions {
                    if positions.contains(index) {
                        flush()
                        cells.append([])
                    } else {
                        text.append(character)
                    }
                } else if character == "\\", characters.first == "|" {
                    text.append(characters.removeFirst())
                    position += 1
                } else if character == "|" {
                    flush()
                    cells.append([])
                } else {
                    text.append(character)
                }
            }
            flush()
        }
        return cells
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
