package se.lindskogen.hakkerneus.ui.comments

import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.LinkAnnotation
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.TextLinkStyles
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.style.TextDecoration
import androidx.compose.ui.text.withLink
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.html.CommentBody
import se.lindskogen.hakkerneus.ui.theme.HN

/**
 * Renders a parsed comment: paragraphs with italics and tappable links, and code blocks that
 * scroll sideways (or wrap, per Settings). Taps outside links fall through to the comment (to collapse it).
 */
@Composable
fun CommentText(body: CommentBody, onLink: (String) -> Unit, modifier: Modifier = Modifier) {
    Column(modifier, verticalArrangement = Arrangement.spacedBy(HN.padding)) {
        for (block in body.blocks) {
            when (block) {
                is CommentBody.Block.Paragraph -> Text(paragraph(block.runs, onLink), style = HN.body)
                is CommentBody.Block.Code -> {
                    val size = CodeBlockStyle.size.sp
                    val wraps = CodeBlockStyle.wrapsLines
                    Text(
                        block.text,
                        style = HN.body.copy(fontFamily = FontFamily.Monospace, fontSize = size.sp, lineHeight = (size + 5).sp),
                        softWrap = wraps,
                        modifier = Modifier
                            .fillMaxWidth()
                            .border(0.5.dp, Color.White.copy(alpha = 0.25f))
                            .then(if (wraps) Modifier else Modifier.horizontalScroll(rememberScrollState()))
                            .padding(HN.padding),
                    )
                }
            }
        }
    }
}

private val linkStyles = TextLinkStyles(SpanStyle(color = Color.White, textDecoration = TextDecoration.Underline))

private fun paragraph(runs: List<CommentBody.Run>, onLink: (String) -> Unit): AnnotatedString = buildAnnotatedString {
    for (run in runs) {
        val style = if (run.isItalic) SpanStyle(fontStyle = FontStyle.Italic) else SpanStyle()
        val link = run.link
        if (link != null) {
            withLink(LinkAnnotation.Clickable(link, linkStyles) { onLink(link) }) {
                withStyle(style) { append(run.text) }
            }
        } else {
            withStyle(style) { append(run.text) }
        }
    }
}
