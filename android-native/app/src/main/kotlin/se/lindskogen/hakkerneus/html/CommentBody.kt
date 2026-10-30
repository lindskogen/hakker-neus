package se.lindskogen.hakkerneus.html

/** A parsed HN comment: paragraphs of styled runs and preformatted code blocks. */
data class CommentBody(val blocks: List<Block>) {
    sealed interface Block {
        data class Paragraph(val runs: List<Run>) : Block
        data class Code(val text: String) : Block
    }

    data class Run(val text: String, val isItalic: Boolean = false, val link: String? = null)

    /** Text for copying: paragraphs separated by blank lines. */
    val plainText: String
        get() = blocks.joinToString("\n\n") { block ->
            when (block) {
                is Block.Paragraph -> block.runs.joinToString("") { it.text }
                is Block.Code -> block.text
            }
        }

    companion object {
        /**
         * Parses the HTML subset HN emits: `<p>`, `<i>`, `<a href>`, `<pre><code>` and entities.
         * Same rules as the iOS parser, so both apps render comments the same way.
         */
        fun parse(html: String): CommentBody {
            val parser = Parser()
            var rest = html
            while (rest.isNotEmpty()) {
                val open = rest.indexOf('<')
                if (open < 0) {
                    parser.text(rest)
                    break
                }
                if (open > 0) parser.text(rest.substring(0, open))
                val close = rest.indexOf('>', open)
                if (close < 0) {
                    // A stray "<" with no closing ">" is just text.
                    parser.text(rest.substring(open))
                    break
                }
                parser.tag(rest.substring(open + 1, close))
                rest = rest.substring(close + 1)
            }
            return CommentBody(parser.finish())
        }
    }
}

private class Parser {
    private val blocks = mutableListOf<CommentBody.Block>()
    private var runs = mutableListOf<CommentBody.Run>()
    private var italicDepth = 0
    private var link: String? = null
    private var code: StringBuilder? = null

    fun text(raw: String) {
        val decoded = HtmlText.decodeEntities(raw)
        code?.let {
            it.append(decoded)
            return
        }
        // Outside <pre>, newlines are whitespace, as in a browser.
        val text = decoded.replace('\n', ' ')
        val run = CommentBody.Run(text, italicDepth > 0, link)
        val last = runs.lastOrNull()
        if (last != null && last.isItalic == run.isItalic && last.link == run.link) {
            runs[runs.lastIndex] = last.copy(text = last.text + text)
        } else {
            runs += run
        }
    }

    fun tag(raw: String) {
        val closing = raw.startsWith("/")
        val body = if (closing) raw.drop(1) else raw
        val name = body.takeWhile { it.isLetterOrDigit() }.lowercase()
        when {
            name == "p" && !closing -> flushParagraph()
            name == "pre" && !closing -> {
                flushParagraph()
                code = StringBuilder()
            }
            name == "pre" && closing -> flushCode()
            (name == "i" || name == "em") && !closing -> italicDepth++
            (name == "i" || name == "em") && closing -> italicDepth = maxOf(0, italicDepth - 1)
            name == "a" && !closing -> link = href(body)
            name == "a" && closing -> link = null
            // </p>, <code>, </code> and anything unknown carry no meaning of their own.
        }
    }

    fun finish(): List<CommentBody.Block> {
        flushCode()
        flushParagraph()
        return blocks
    }

    private fun flushParagraph() {
        if (code != null) return
        val cleaned = runs.filter { it.text.isNotEmpty() }.toMutableList()
        runs = mutableListOf()
        if (cleaned.isEmpty()) return
        cleaned[0] = cleaned[0].copy(text = cleaned[0].text.trimStart())
        cleaned[cleaned.lastIndex] = cleaned.last().copy(text = cleaned.last().text.trimEnd())
        val kept = cleaned.filter { it.text.isNotEmpty() }
        if (kept.isNotEmpty()) blocks += CommentBody.Block.Paragraph(kept)
    }

    private fun flushCode() {
        val text = code ?: return
        code = null
        // HN keeps the 4-space indent that marks a code block in its input; drop it.
        val lines = text.split("\n").map { if (it.startsWith("    ")) it.drop(4) else it }.toMutableList()
        while (lines.isNotEmpty() && lines.last().isBlank()) lines.removeAt(lines.lastIndex)
        while (lines.isNotEmpty() && lines.first().isBlank()) lines.removeAt(0)
        if (lines.isNotEmpty()) blocks += CommentBody.Block.Code(lines.joinToString("\n"))
    }

    private fun href(tag: String): String? {
        val match = Regex("""href\s*=\s*"([^"]*)"""", RegexOption.IGNORE_CASE).find(tag) ?: return null
        val value = HtmlText.decodeEntities(match.groupValues[1])
        // HN sometimes links relatively, e.g. href="item?id=123".
        return runCatching { java.net.URI("https://news.ycombinator.com/").resolve(value).toString() }.getOrNull()
    }
}
