package se.lindskogen.hakkerneus.account

/**
 * HN's comment formatting, for showing a just-posted comment before Algolia has it (as on iOS):
 * blank lines separate paragraphs, `*text*` is italic, two-space indented lines are code,
 * bare URLs become links.
 */
object HnFormatting {
    fun html(plain: String): String = plain.replace("\r\n", "\n")
        .split("\n\n")
        .map { it.trim('\n') }
        .filter { it.isNotBlank() }
        .mapIndexed { index, paragraph ->
            val lines = paragraph.split("\n")
            if (lines.all { it.startsWith("  ") }) {
                "<pre><code>" + lines.joinToString("\n") { "  " + escape(it) } + "</code></pre>"
            } else {
                val inline = linkify(italicize(escape(lines.joinToString(" "))))
                if (index == 0) inline else "<p>$inline"
            }
        }
        .joinToString("")

    private fun escape(text: String) = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    private fun italicize(text: String) = text.replace(Regex("\\*([^*\\n]+)\\*"), "<i>$1</i>")
    private fun linkify(text: String) = text.replace(Regex("(https?://[^\\s<]+[^\\s<.,;:!?)\\]])"), "<a href=\"$1\">$1</a>")
}
