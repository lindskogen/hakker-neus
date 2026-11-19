package se.lindskogen.hakkerneus.ui.comments

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.html.CommentBody
import se.lindskogen.hakkerneus.ui.theme.HN

private val ruleColor = Color.White.copy(alpha = 0.25f)
private val maximumCellWidth = 260.dp

/**
 * A Markdown table: a grid with a bold header row, hairline rules and the code block's border,
 * scrolling sideways when it's wider than the comment. Columns are as wide as their widest cell
 * (up to a cap, past which cells wrap) and spread out to fill the comment's width.
 */
@Composable
internal fun TableBlock(table: CommentBody.Table, onLink: (String) -> Unit) {
    val size = CommentTextStyle.size.points
    val style = HN.body.copy(fontSize = size.sp, lineHeight = (size + 6).sp)
    val rows = listOf(table.header) + table.rows
    val columns = table.alignments.size

    BoxWithConstraints(Modifier.fillMaxWidth().border(0.5.dp, ruleColor)) {
        val viewportWidth = constraints.maxWidth
        val headerBackground: @Composable () -> Unit = { Box(Modifier.background(Color.White.copy(alpha = 0.08f))) }
        val cellTexts: @Composable () -> Unit = {
            rows.forEachIndexed { index, row ->
                for (cell in row) {
                    val text = paragraph(cell, onLink)
                    Text(
                        if (index == 0) buildAnnotatedString { withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(text) } } else text,
                        style = style,
                    )
                }
            }
        }
        val ruleLines: @Composable () -> Unit = { repeat(rows.size - 1 + columns - 1) { Box(Modifier.background(ruleColor)) } }

        Layout(
            contents = listOf(headerBackground, cellTexts, ruleLines),
            modifier = Modifier.horizontalScroll(rememberScrollState()),
        ) { (background, cells, rules), _ ->
            val padH = HN.padding.roundToPx()
            val padV = (HN.padding / 2).roundToPx()
            val cellConstraints = Constraints(maxWidth = maximumCellWidth.roundToPx())
            val placed = cells.map { it.measure(cellConstraints) }
            fun cell(row: Int, column: Int) = placed[row * columns + column]

            val natural = (0 until columns).map { c -> rows.indices.maxOf { r -> cell(r, c).width } + 2 * padH }
            // Share out any room beyond the table's natural width evenly between the columns.
            val extra = maxOf(0, viewportWidth - natural.sum()) / maxOf(columns, 1)
            val widths = natural.map { it + extra }
            val heights = rows.indices.map { r -> (0 until columns).maxOf { c -> cell(r, c).height } + 2 * padV }
            val width = widths.sum()
            val height = heights.sum()
            val hairline = 1

            val header = background.single().measure(Constraints.fixed(width, heights.first()))
            val horizontal = rules.take(rows.size - 1).map { it.measure(Constraints.fixed(width, hairline)) }
            val vertical = rules.drop(rows.size - 1).map { it.measure(Constraints.fixed(hairline, height)) }

            layout(width, height) {
                header.place(0, 0)
                var y = 0
                for (r in rows.indices) {
                    var x = 0
                    for (c in 0 until columns) {
                        val placeable = cell(r, c)
                        val room = widths[c] - 2 * padH
                        val offset = when (table.alignments[c]) {
                            CommentBody.Table.Alignment.Leading -> 0
                            CommentBody.Table.Alignment.Center -> (room - placeable.width) / 2
                            CommentBody.Table.Alignment.Trailing -> room - placeable.width
                        }
                        placeable.place(x + padH + offset, y + padV)
                        x += widths[c]
                    }
                    y += heights[r]
                    if (r < rows.size - 1) horizontal[r].place(0, y)
                }
                var x = 0
                for (c in 0 until columns - 1) {
                    x += widths[c]
                    vertical[c].place(x, 0)
                }
            }
        }
    }
}
