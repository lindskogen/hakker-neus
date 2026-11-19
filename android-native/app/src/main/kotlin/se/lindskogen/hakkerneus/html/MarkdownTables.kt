package se.lindskogen.hakkerneus.html

import se.lindskogen.hakkerneus.html.CommentBody.Block
import se.lindskogen.hakkerneus.html.CommentBody.Run
import se.lindskogen.hakkerneus.html.CommentBody.Table

/**
 * Finds Markdown pipe tables in a parsed comment, GitHub style:
 *
 * ```
 * | Name  | Size |
 * | :---- | ---: |
 * | Alpha |   12 |
 * ```
 *
 * A header row, then a delimiter row with the same number of cells (`---`, with `:` for
 * alignment), then body rows until the first line without a `|`. Leading and trailing pipes
 * are optional and `\|` is a literal pipe. HN shows single newlines as spaces, so people often
 * put a blank line between rows: rows split over paragraphs count as one table. A code block
 * that holds nothing but a table becomes a table too.
 *
 * ASCII grid tables, as psql, MySQL and pandoc draw them, count too:
 *
 * ```
 * +-------+------+
 * | Name  | Size |
 * +=======+======+
 * | Alpha |   12 |
 * +-------+------+
 * ```
 *
 * The `+` in the borders mark the columns, so a `|` inside a cell stays text. Rows before
 * the first rule under the top border are the header. When every body row has a rule under
 * it, a row can wrap over several lines, as in pandoc; otherwise each line is a row.
 * Columns take the alignment of `:` in the rule under the header, as in pandoc, or else
 * line up right when every body cell is pushed to the right. Same rules as the iOS app.
 */
object MarkdownTables {
    /** Replaces tables in [blocks] with [Block.Table]s, and turns the newlines left in paragraphs into spaces. */
    fun extract(blocks: List<Block>): List<Block> {
        val result = mutableListOf<Block>()
        // Lines of the paragraphs since the last code block, with the paragraph each came from.
        val lines = mutableListOf<Line>()
        var paragraph = 0

        fun flushLines() {
            result += scan(lines)
            lines.clear()
        }

        for (block in blocks) {
            when (block) {
                is Block.Paragraph -> {
                    val index = paragraph++
                    lines += split(block.runs).map { Line(index, it) }
                }
                is Block.Code -> {
                    flushLines()
                    result += tableInCode(block.text)?.let { Block.Table(it) } ?: block
                }
                is Block.Table -> {
                    flushLines()
                    result += block
                }
            }
        }
        flushLines()
        return result
    }

    // Finding tables

    private class Line(val paragraph: Int, val runs: List<Run>)

    private fun scan(lines: List<Line>): List<Block> {
        val blocks = mutableListOf<Block>()
        val prose = mutableListOf<Line>()
        val runs = lines.map { it.runs }
        var index = 0
        while (index < lines.size) {
            val found = anyTableAt(index, runs)
            if (found != null) {
                blocks += paragraphs(prose)
                prose.clear()
                blocks += Block.Table(found.first)
                index += found.second
            } else {
                prose += lines[index]
                index++
            }
        }
        return blocks + paragraphs(prose)
    }

    /** A code block is a table only if every line of it belongs to the table. */
    private fun tableInCode(code: String): Table? {
        val lines = code.split("\n").map { listOf(Run(it)) }
        val found = anyTableAt(0, lines) ?: return null
        return found.first.takeIf { found.second == lines.size }
    }

    /** The table starting at `lines[start]`, and how many lines it takes up. */
    private fun anyTableAt(start: Int, lines: List<List<Run>>) = pipeTableAt(start, lines) ?: gridTableAt(start, lines)

    /** The pipe table whose header row is `lines[start]`, and how many lines it takes up. */
    private fun pipeTableAt(start: Int, lines: List<List<Run>>): Pair<Table, Int>? {
        if (start + 1 >= lines.size || !hasPipe(lines[start]) || !hasPipe(lines[start + 1])) return null
        val alignments = alignments(lines[start + 1]) ?: return null
        val header = cells(lines[start])
        if (header.size != alignments.size) return null

        val rows = mutableListOf<List<List<Run>>>()
        var end = start + 2
        while (end < lines.size && hasPipe(lines[end])) {
            // Like GitHub: short rows are padded with empty cells, extra cells dropped.
            val row = cells(lines[end]).take(header.size)
            rows += row + List(header.size - row.size) { emptyList() }
            end++
        }
        return Table(alignments, header, rows) to end - start
    }

    private val delimiterCell = Regex(":?-+:?")

    /** The alignment of each column if [line] is a delimiter row such as `| :--- | ---: |`. */
    private fun alignments(line: List<Run>): List<Table.Alignment>? {
        val cells = cells(line).map(::text)
        if (cells.isEmpty() || cells.any { !delimiterCell.matches(it) }) return null
        return cells.map {
            when {
                it.startsWith(":") && it.endsWith(":") -> Table.Alignment.Center
                it.endsWith(":") -> Table.Alignment.Trailing
                else -> Table.Alignment.Leading
            }
        }
    }

    // Grid tables

    /** The grid table whose top border is `lines[start]`, and how many lines it takes up. */
    private fun gridTableAt(start: Int, lines: List<List<Run>>): Pair<Table, Int>? {
        val top = text(lines[start]).trim()
        if (!isBorder(top)) return null
        // Where the columns' edges are, counted from the first character of the line.
        val edges = top.indices.filter { top[it] == '+' }
        val columns = edges.size - 1

        // The rows between each pair of rules, and the rules.
        val sections = mutableListOf(mutableListOf<List<Run>>())
        val rules = mutableListOf(top)
        var end = start + 1
        while (end < lines.size) {
            val line = text(lines[end]).trim()
            when {
                isBorder(line) -> {
                    rules += line
                    sections += mutableListOf<List<Run>>()
                }
                line.length >= 2 && line.first() == '|' && line.last() == '|' -> sections.last() += lines[end]
                else -> break
            }
            end++
        }
        sections.removeAll { it.isEmpty() }
        val first = sections.firstOrNull() ?: return null

        // A row wrapped over several lines joins each cell's lines with spaces.
        fun row(rowLines: List<List<Run>>): List<List<Run>> {
            val split = rowLines.map { gridCells(it, edges, columns) }
            return (0 until columns).map { column ->
                trimmed(split.map { it[column] }.reduce { joined, cell -> joined + Run(" ") + cell })
            }
        }

        val header: List<List<Run>>
        val body: List<List<List<Run>>>
        val bodyLines: List<List<Run>>
        if (sections.size == 1) {
            // No rule under a header: the first line is the header.
            header = row(listOf(first[0]))
            bodyLines = first.drop(1)
            body = bodyLines.map { row(listOf(it)) }
        } else {
            header = row(first)
            val rest = sections.drop(1)
            bodyLines = rest.flatten()
            body = if (rest.size > 1) rest.map(::row) else bodyLines.map { row(listOf(it)) }
        }

        val separator = rules.getOrNull(1) ?: top
        val alignments = ruleAlignments(separator, edges) ?: (0 until columns).map { column ->
            inferredAlignment(bodyLines.map { gridCells(it, edges, columns, trimming = false)[column] })
        }
        return Table(alignments, header, body) to end - start
    }

    /** `+----+====+` or `+:---+---:+`. */
    private fun isBorder(line: String) =
        line.length >= 3 && line.first() == '+' && line.last() == '+' &&
            line.all { it in "+-=:" } && "++" !in line && line.any { it == '-' || it == '=' }

    /**
     * The cells of a grid row, split at the pipes below the border's `+`, or at every pipe when
     * the row doesn't line up with the border (wide characters, say).
     */
    private fun gridCells(line: List<Run>, edges: List<Int>, columns: Int, trimming: Boolean = true): List<List<Run>> {
        val characters = text(line)
        val indent = characters.takeWhile { it.isWhitespace() }.length
        val positions = edges.map { it + indent }
        val lined = positions.all { it < characters.length && characters[it] == '|' }
        val split = (if (lined) rawCells(line, positions.toSet()) else rawCells(line)).drop(1).dropLast(1)
        val cells = split.take(columns) + List(maxOf(0, columns - split.size)) { emptyList() }
        return if (trimming) cells.map(::trimmed) else cells
    }

    /** The alignments a rule's colons give, or null if it has none. */
    private fun ruleAlignments(rule: String, edges: List<Int>): List<Table.Alignment>? {
        if (':' !in rule || rule.length <= edges.last()) return null
        return edges.zipWithNext { left, right ->
            val start = rule[left + 1] == ':'
            val end = rule[right - 1] == ':'
            when {
                start && end -> Table.Alignment.Center
                end -> Table.Alignment.Trailing
                else -> Table.Alignment.Leading
            }
        }
    }

    /** Right-aligned when every filled cell has at most one space after it and one has more before. */
    private fun inferredAlignment(cells: List<List<Run>>): Table.Alignment {
        val filled = cells.map(::text).filter { it.isNotBlank() }
        val trailing = filled.all { it.length - it.trimEnd(' ').length <= 1 }
        val pushed = filled.any { it.length - it.trimStart(' ').length > 1 }
        return if (filled.isNotEmpty() && trailing && pushed) Table.Alignment.Trailing else Table.Alignment.Leading
    }

    // Splitting

    /** Splits runs at newlines into lines of runs. */
    private fun split(runs: List<Run>): List<List<Run>> {
        val lines = mutableListOf(mutableListOf<Run>())
        for (run in runs) {
            run.text.split("\n").forEachIndexed { index, part ->
                if (index > 0) lines += mutableListOf<Run>()
                if (part.isNotEmpty()) lines.last() += run.copy(text = part)
            }
        }
        return lines
    }

    private fun hasPipe(line: List<Run>): Boolean {
        var escaped = false
        for (c in text(line)) {
            if (c == '|' && !escaped) return true
            escaped = c == '\\' && !escaped
        }
        return false
    }

    private fun text(line: List<Run>) = line.joinToString("") { it.text }

    /** The trimmed cells of a pipe-table row, keeping each cell's italics and links. */
    private fun cells(line: List<Run>): List<List<Run>> {
        val cells = rawCells(line).toMutableList()
        val row = text(line).trim()
        if (row.startsWith("|")) cells.removeAt(0)
        if (row.endsWith("|") && !row.endsWith("\\|") && cells.isNotEmpty()) cells.removeAt(cells.lastIndex)
        return cells.map(::trimmed)
    }

    /**
     * A row split into untrimmed cells at every unescaped pipe, or only at the pipes at
     * [positions] (character offsets in the line), keeping italics and links.
     */
    private fun rawCells(line: List<Run>, positions: Set<Int>? = null): List<List<Run>> {
        val cells = mutableListOf(mutableListOf<Run>())
        var position = 0
        for (run in line) {
            val text = StringBuilder()
            fun flush() {
                if (text.isNotEmpty()) cells.last() += run.copy(text = text.toString())
                text.clear()
            }
            var i = 0
            while (i < run.text.length) {
                val c = run.text[i]
                when {
                    positions != null -> if (position + i in positions) {
                        flush()
                        cells += mutableListOf<Run>()
                    } else {
                        text.append(c)
                    }
                    c == '\\' && run.text.getOrNull(i + 1) == '|' -> {
                        text.append('|')
                        i++
                    }
                    c == '|' -> {
                        flush()
                        cells += mutableListOf<Run>()
                    }
                    else -> text.append(c)
                }
                i++
            }
            position += run.text.length
            flush()
        }
        return cells
    }

    // Paragraphs

    /** Joins the lines that aren't part of a table back into their paragraphs. */
    private fun paragraphs(lines: List<Line>): List<Block> {
        val blocks = mutableListOf<Block>()
        var index = 0
        while (index < lines.size) {
            val runs = mutableListOf<Run>()
            val paragraph = lines[index].paragraph
            while (index < lines.size && lines[index].paragraph == paragraph) {
                if (runs.isNotEmpty()) runs += Run(" ")
                runs += lines[index].runs
                index++
            }
            val kept = trimmed(runs)
            if (kept.isNotEmpty()) blocks += Block.Paragraph(kept)
        }
        return blocks
    }

    /** Merges neighbouring runs that look the same and trims whitespace from both ends. */
    private fun trimmed(runs: List<Run>): List<Run> {
        val merged = mutableListOf<Run>()
        for (run in runs) {
            if (run.text.isEmpty()) continue
            val last = merged.lastOrNull()
            if (last != null && last.isItalic == run.isItalic && last.link == run.link) {
                merged[merged.lastIndex] = last.copy(text = last.text + run.text)
            } else {
                merged += run
            }
        }
        if (merged.isEmpty()) return merged
        merged[0] = merged[0].copy(text = merged[0].text.trimStart())
        merged[merged.lastIndex] = merged.last().copy(text = merged.last().text.trimEnd())
        return merged.filter { it.text.isNotEmpty() }
    }
}

/** The table as Markdown with its columns lined up, for copying. */
val Table.markdown: String
    get() {
        val text = (listOf(header) + rows).map { row -> row.map { cell -> cell.joinToString("") { it.text }.replace("|", "\\|") } }
        val widths = alignments.indices.map { column -> maxOf(3, text.maxOf { it[column].length }) }

        fun line(cells: List<String>) = "| " + cells.joinToString(" | ") + " |"
        fun padded(cell: String, column: Int): String {
            val space = widths[column] - cell.length
            return when (alignments[column]) {
                Table.Alignment.Leading -> cell + " ".repeat(space)
                Table.Alignment.Trailing -> " ".repeat(space) + cell
                Table.Alignment.Center -> " ".repeat(space / 2) + cell + " ".repeat(space - space / 2)
            }
        }

        val delimiter = alignments.mapIndexed { column, alignment ->
            when (alignment) {
                Table.Alignment.Leading -> "-".repeat(widths[column])
                Table.Alignment.Trailing -> "-".repeat(widths[column] - 1) + ":"
                Table.Alignment.Center -> ":" + "-".repeat(widths[column] - 2) + ":"
            }
        }
        return (listOf(line(text[0].mapIndexed { i, cell -> padded(cell, i) }), line(delimiter)) +
            text.drop(1).map { row -> line(row.mapIndexed { i, cell -> padded(cell, i) }) })
            .joinToString("\n")
    }
