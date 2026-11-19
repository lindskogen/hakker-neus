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
 * that holds nothing but a table becomes a table too. Same rules as the iOS app.
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
            val found = tableAt(index, runs)
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
        val found = tableAt(0, lines) ?: return null
        return found.first.takeIf { found.second == lines.size }
    }

    /** The table whose header row is `lines[start]`, and how many lines it takes up. */
    private fun tableAt(start: Int, lines: List<List<Run>>): Pair<Table, Int>? {
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
        val cells = cells(line).map { cell -> cell.joinToString("") { it.text } }
        if (cells.isEmpty() || cells.any { !delimiterCell.matches(it) }) return null
        return cells.map {
            when {
                it.startsWith(":") && it.endsWith(":") -> Table.Alignment.Center
                it.endsWith(":") -> Table.Alignment.Trailing
                else -> Table.Alignment.Leading
            }
        }
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
        for (c in line.joinToString("") { it.text }) {
            if (c == '|' && !escaped) return true
            escaped = c == '\\' && !escaped
        }
        return false
    }

    /** The trimmed cells of a row, keeping each cell's italics and links. */
    private fun cells(line: List<Run>): List<List<Run>> {
        val cells = mutableListOf(mutableListOf<Run>())
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
            flush()
        }

        val row = line.joinToString("") { it.text }.trim()
        if (row.startsWith("|")) cells.removeAt(0)
        if (row.endsWith("|") && !row.endsWith("\\|") && cells.isNotEmpty()) cells.removeAt(cells.lastIndex)
        return cells.map(::trimmed)
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
