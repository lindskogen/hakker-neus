package se.lindskogen.hakkerneus

import org.junit.Assert.assertEquals
import org.junit.Test
import se.lindskogen.hakkerneus.html.CommentBody
import se.lindskogen.hakkerneus.html.CommentBody.Block.Code
import se.lindskogen.hakkerneus.html.CommentBody.Block.Paragraph
import se.lindskogen.hakkerneus.html.CommentBody.Block.Table as TableBlock
import se.lindskogen.hakkerneus.html.CommentBody.Run
import se.lindskogen.hakkerneus.html.CommentBody.Table.Alignment
import se.lindskogen.hakkerneus.html.HtmlText

/** Same fixtures as the iOS CommentBodyTests (from the RN app's CommentsSink). */
class CommentBodyTest {
    @Test
    fun italicQuote() {
        val html = "&gt; <i>The metro is efficient &quot;intra muros&quot;.</i><p>Yes.  We didn&#x27;t bother."
        assertEquals(
            listOf(
                Paragraph(listOf(Run("> "), Run("The metro is efficient \"intra muros\".", isItalic = true))),
                Paragraph(listOf(Run("Yes.  We didn't bother."))),
            ),
            CommentBody.parse(html).blocks,
        )
    }

    @Test
    fun linksIncludingRelativeOnes() {
        val html = "[0] <a href=\"https:&#x2F;&#x2F;news.ycombinator.com&#x2F;item?id=2192629\" rel=\"nofollow\">link</a> and <a href=\"item?id=123\">this</a>"
        val runs = (CommentBody.parse(html).blocks.single() as Paragraph).runs
        assertEquals("https://news.ycombinator.com/item?id=2192629", runs[1].link)
        assertEquals("https://news.ycombinator.com/item?id=123", runs[3].link)
    }

    @Test
    fun codeBlocksLoseTheirIndent() {
        val html = "Like this:<p><pre><code>    import requests\n    \n    response = requests.get(&#x27;x&#x27;)\n</code></pre>\nClever idea"
        assertEquals(
            listOf(
                Paragraph(listOf(Run("Like this:"))),
                Code("import requests\n\nresponse = requests.get('x')"),
                Paragraph(listOf(Run("Clever idea"))),
            ),
            CommentBody.parse(html).blocks,
        )
    }

    @Test
    fun newlinesOutsideCodeAreSpaces() {
        assertEquals(listOf(Paragraph(listOf(Run("One. Two")))), CommentBody.parse("One.\nTwo").blocks)
    }

    @Test
    fun malformedInputDoesNotCrash() {
        assertEquals(emptyList<Any>(), CommentBody.parse("").blocks)
        assertEquals(listOf(Paragraph(listOf(Run("a < b")))), CommentBody.parse("a < b").blocks)
        assertEquals(listOf(Code("unterminated")), CommentBody.parse("<pre><code>unterminated").blocks)
    }

    // Markdown tables: same cases as the iOS CommentBodyTests.

    private fun cells(vararg texts: String) = texts.map { if (it.isEmpty()) emptyList() else listOf(Run(it)) }

    @Test
    fun tableOnSingleNewlines() {
        val html = "Benchmarks:\n| Name | Time |\n|:-----|-----:|\n| foo  | 1.2s |\n| bar  | 10s  |\nSo foo wins.<p>Next"
        assertEquals(
            listOf(
                Paragraph(listOf(Run("Benchmarks:"))),
                TableBlock(CommentBody.Table(listOf(Alignment.Leading, Alignment.Trailing), cells("Name", "Time"), listOf(cells("foo", "1.2s"), cells("bar", "10s")))),
                Paragraph(listOf(Run("So foo wins."))),
                Paragraph(listOf(Run("Next"))),
            ),
            CommentBody.parse(html).blocks,
        )
    }

    @Test
    fun tableWithRowsInSeparateParagraphs() {
        val html = "Intro<p>a | b | c<p>--- | :-: | ---<p>1 | 2<p>4 | 5 | 6 | 7<p>Outro"
        assertEquals(
            listOf(
                Paragraph(listOf(Run("Intro"))),
                TableBlock(
                    CommentBody.Table(
                        listOf(Alignment.Leading, Alignment.Center, Alignment.Leading),
                        cells("a", "b", "c"),
                        listOf(cells("1", "2", ""), cells("4", "5", "6")),
                    ),
                ),
                Paragraph(listOf(Run("Outro"))),
            ),
            CommentBody.parse(html).blocks,
        )
    }

    @Test
    fun tableCellsKeepLinksItalicsAndEscapedPipes() {
        val html = "| Site | Note |\n| --- | --- |\n| <a href=\"https://example.com\">example</a> | <i>a \\| b</i> |"
        val table = (CommentBody.parse(html).blocks.single() as TableBlock).table
        assertEquals(listOf(listOf(Run("example", link = "https://example.com")), listOf(Run("a | b", isItalic = true))), table.rows.single())
    }

    @Test
    fun tableInCodeBlock() {
        val html = "<pre><code>  | x | y |\n  |---|---|\n  | 1 | 2 |\n</code></pre>"
        assertEquals(
            listOf(TableBlock(CommentBody.Table(listOf(Alignment.Leading, Alignment.Leading), cells("x", "y"), listOf(cells("1", "2"))))),
            CommentBody.parse(html).blocks,
        )
        // Code that only contains a table somewhere stays code.
        assertEquals(Code("let a = 1\n| x |\n|---|"), CommentBody.parse("<pre><code>let a = 1\n| x |\n|---|</code></pre>").blocks.single())
    }

    @Test
    fun notTables() {
        // Pipes without a delimiter row, a rule without pipes, and mismatched column counts.
        for (html in listOf("a | b\nc | d", "a | b<p>---", "a | b\n--- | --- | ---", "| a |\n|:-:-|", "x || y")) {
            assertEquals(html, 0, CommentBody.parse(html).blocks.count { it is TableBlock })
        }
        assertEquals(listOf(Paragraph(listOf(Run("a | b c | d")))), CommentBody.parse("a | b\nc | d").blocks)
    }

    @Test
    fun tablePlainTextIsAlignedMarkdown() {
        val html = "Sizes<p>|Name|Size|Mid|\n|-|-:|:-:|\n|Alpha|12|x|\n|B|1234|yes|"
        assertEquals(
            """
            Sizes

            | Name  | Size | Mid |
            | ----- | ---: | :-: |
            | Alpha |   12 |  x  |
            | B     | 1234 | yes |
            """.trimIndent(),
            CommentBody.parse(html).plainText,
        )
    }

    // ASCII grid tables: same cases as the iOS CommentBodyTests.

    /** A comment from the wild: a psql-style grid indented into a code block. */
    private val modelsTable = """
          +-------------------------------+--------------+--------+--------+----------+-------+
          |              Lab              |      XL      |   L    |   M+   |    M     | S/XS  |
          +-------------------------------+--------------+--------+--------+----------+-------+
          | Google (Gemini 4 Family #1)   |              | Argon  |        |          |       |
          | Google (Gemini 4 Family #2)   |              | Carbon | Neon   | Hydrogen |       |
          | Anthropic (Claude 5.2 Family) | Fable/Mythos |        |        |          |       |
          | Anthropic (Claude 5.5 Family) |              | Opus   |        | Sonnet   | Haiku |
          | OpenAI (GPT 6.2 Family)       | Astra        | Sol    |        |          |       |
          | OpenAI (GPT 6.1 Family)       |              |        |        | Terra    |       |
          | OpenAI (GPT 6 Family)         |              |        |        |          | Luna  |
          +-------------------------------+--------------+--------+--------+----------+-------+
    """.trimIndent().prependIndent("  ")

    @Test
    fun gridTableInCodeBlock() {
        val html = "Edited: For formatting and from feedback<p>So if I am getting this right?<p><pre><code>$modelsTable\n</code></pre>"
        val blocks = CommentBody.parse(html).blocks
        assertEquals(Paragraph(listOf(Run("So if I am getting this right?"))), blocks[1])
        val table = (blocks[2] as TableBlock).table
        assertEquals(cells("Lab", "XL", "L", "M+", "M", "S/XS"), table.header)
        assertEquals(List(6) { Alignment.Leading }, table.alignments)
        assertEquals(7, table.rows.size)
        assertEquals(cells("Anthropic (Claude 5.5 Family)", "", "Opus", "", "Sonnet", "Haiku"), table.rows[3])
        assertEquals(cells("OpenAI (GPT 6 Family)", "", "", "", "", "Luna"), table.rows[6])
        assertEquals(3, blocks.size)
    }

    @Test
    fun gridTableWithWrappedRowsAndRuleAlignment() {
        // Pandoc: a rule under every row, so rows wrap; colons in the header rule align.
        val html = """
            +-------+-----------+------:+
            | Name  | Notes     | Size  |
            +=======+:=========:+======:+
            | Alpha | the first | 12    |
            |       | one       |       |
            +-------+-----------+-------+
            | B     | a | pipe  | 1234  |
            +-------+-----------+-------+
        """.trimIndent()
        val table = (CommentBody.parse("<pre><code>$html</code></pre>").blocks.single() as TableBlock).table
        assertEquals(listOf(Alignment.Leading, Alignment.Center, Alignment.Trailing), table.alignments)
        assertEquals(listOf(cells("Alpha", "the first one", "12"), cells("B", "a | pipe", "1234")), table.rows)
    }

    @Test
    fun gridTableInTextInfersRightAlignment() {
        // Typed straight into the comment, one line per row; numbers pushed right.
        val html = "Results:\n+------+-------+\n| Name | Count |\n+------+-------+\n| foo  |     1 |\n| bar  |   200 |\n+------+-------+\nThanks"
        val blocks = CommentBody.parse(html).blocks
        assertEquals(Paragraph(listOf(Run("Results:"))), blocks[0])
        val table = (blocks[1] as TableBlock).table
        assertEquals(listOf(Alignment.Leading, Alignment.Trailing), table.alignments)
        assertEquals(listOf(cells("foo", "1"), cells("bar", "200")), table.rows)
        assertEquals(Paragraph(listOf(Run("Thanks"))), blocks[2])
    }

    @Test
    fun notGridTables() {
        for (html in listOf("+---+", "<pre><code>+--+--+\nnot a row\n+--+--+</code></pre>", "a +-+ b", "+++\n| a |")) {
            assertEquals(html, 0, CommentBody.parse(html).blocks.count { it is TableBlock })
        }
    }

    @Test
    fun entities() {
        assertEquals("that's \"it\" & > >", HtmlText.decodeEntities("that&#x27;s &quot;it&quot; &amp; &#62; &gt;"))
        assertEquals("AT&T; R&D &bogus;", HtmlText.decodeEntities("AT&T; R&D &bogus;"))
    }
}
