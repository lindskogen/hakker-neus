package se.lindskogen.hakkerneus

import org.junit.Assert.assertEquals
import org.junit.Test
import se.lindskogen.hakkerneus.html.CommentBody
import se.lindskogen.hakkerneus.html.CommentBody.Block.Code
import se.lindskogen.hakkerneus.html.CommentBody.Block.Paragraph
import se.lindskogen.hakkerneus.html.CommentBody.Run
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

    @Test
    fun entities() {
        assertEquals("that's \"it\" & > >", HtmlText.decodeEntities("that&#x27;s &quot;it&quot; &amp; &#62; &gt;"))
        assertEquals("AT&T; R&D &bogus;", HtmlText.decodeEntities("AT&T; R&D &bogus;"))
    }
}
