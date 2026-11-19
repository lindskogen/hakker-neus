package se.lindskogen.hakkerneus.ui.comments

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.draw.clip
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
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.html.CommentBody
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.theme.HN

private val ruleColor = Color.White.copy(alpha = 0.25f)
private val maximumCellWidth = 260.dp

/** Tables fitted to the width with their corner button, remembered while the app runs. */
private val fittedTables = mutableStateMapOf<CommentBody.Table, Boolean>()

/**
 * A Markdown table: a grid with a bold header row, hairline rules and the code block's border.
 * It scrolls sideways when it's wider than the comment, its columns as wide as their widest cell
 * (up to a cap, past which cells wrap) and spread out to fill the comment's width. A button in
 * its corner, shown only when it's too wide, fits it to the comment's width instead, like a
 * browser: every column gets at least its longest word, the room left goes to the columns
 * with the most text, and cells wrap. The same as iOS.
 */
@Composable
internal fun TableBlock(table: CommentBody.Table, onLink: (String) -> Unit) {
    val size = CommentTextStyle.size.points
    val style = HN.body.copy(fontSize = size.sp, lineHeight = (size + 6).sp)
    val rows = listOf(table.header) + table.rows
    val columns = table.alignments.size
    val fits = fittedTables[table] == true
    val scroll = rememberScrollState()

    BoxWithConstraints(Modifier.fillMaxWidth().border(0.5.dp, ruleColor)) {
        val viewportWidth = constraints.maxWidth
        val headerBackground: @Composable () -> Unit = { Box(Modifier.background(Color.White.copy(alpha = 0.08f))) }
        val cellTexts: @Composable () -> Unit = {
            rows.forEachIndexed { index, row ->
                row.forEachIndexed { column, cell ->
                    val text = paragraph(cell, onLink)
                    Text(
                        if (index == 0) buildAnnotatedString { withStyle(SpanStyle(fontWeight = FontWeight.Bold)) { append(text) } } else text,
                        // Wrapped cells fill their column, so line up their lines within it.
                        style = if (fits) style.copy(textAlign = table.alignments[column].textAlign) else style,
                    )
                }
            }
        }
        val ruleLines: @Composable () -> Unit = { repeat(rows.size - 1 + columns - 1) { Box(Modifier.background(ruleColor)) } }
        val fitButton: @Composable () -> Unit = {
            Box(
                Modifier
                    .clip(RoundedCornerShape(5.dp))
                    .background(HN.backgroundDark.copy(alpha = 0.9f))
                    .border(0.5.dp, ruleColor, RoundedCornerShape(5.dp))
                    .clickable(onClickLabel = if (fits) "Scroll table sideways" else "Fit table to width") {
                        if (fits) {
                            fittedTables.remove(table)
                        } else {
                            fittedTables[table] = true
                        }
                    }
                    .padding(5.dp),
            ) {
                Icon(
                    if (fits) HnIcons.scrollSideways else HnIcons.fitWidth,
                    contentDescription = if (fits) "Scroll table sideways" else "Fit table to width",
                    tint = Color.White.copy(alpha = 0.8f),
                    modifier = Modifier.size(14.dp),
                )
            }
        }

        Layout(
            contents = listOf(headerBackground, cellTexts, ruleLines, fitButton),
            modifier = if (fits) Modifier else Modifier.horizontalScroll(scroll),
        ) { (background, cells, rules, button), _ ->
            val padH = HN.padding.roundToPx()
            val padV = (HN.padding / 2).roundToPx()
            fun index(row: Int, column: Int) = row * columns + column

            val widths: List<Int>
            val placed: List<Placeable>
            // How wide the table would like to be: when that's wider than the comment, it gets the button.
            val naturalWidth: Int
            if (fits) {
                val natural = (0 until columns).map { c -> rows.indices.maxOf { r -> cells[index(r, c)].maxIntrinsicWidth(Constraints.Infinity) } + 2 * padH }
                naturalWidth = natural.sum()
                val minimum = (0 until columns).map { c -> rows.indices.maxOf { r -> cells[index(r, c)].minIntrinsicWidth(Constraints.Infinity) } + 2 * padH }
                widths = fittedWidths(natural, minimum, viewportWidth)
                placed = cells.mapIndexed { i, cell -> cell.measure(Constraints.fixedWidth(maxOf(0, widths[i % columns] - 2 * padH))) }
            } else {
                val cellConstraints = Constraints(maxWidth = maximumCellWidth.roundToPx())
                placed = cells.map { it.measure(cellConstraints) }
                val natural = (0 until columns).map { c -> rows.indices.maxOf { r -> placed[index(r, c)].width } + 2 * padH }
                naturalWidth = natural.sum()
                // Share out any room beyond the table's natural width evenly between the columns.
                val extra = maxOf(0, viewportWidth - natural.sum()) / maxOf(columns, 1)
                widths = natural.map { it + extra }
            }
            fun cell(row: Int, column: Int) = placed[index(row, column)]

            val heights = rows.indices.map { r -> (0 until columns).maxOf { c -> cell(r, c).height } + 2 * padV }
            val width = widths.sum()
            val height = heights.sum()
            val hairline = 1

            val header = background.single().measure(Constraints.fixed(width, heights.first()))
            val horizontal = rules.take(rows.size - 1).map { it.measure(Constraints.fixed(width, hairline)) }
            val vertical = rules.drop(rows.size - 1).map { it.measure(Constraints.fixed(hairline, height)) }
            val toggle = button.single().measure(Constraints()).takeIf { naturalWidth > viewportWidth }
            val inset = 3.dp.roundToPx()

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
                // Floats in the visible top-right corner, however far the table has scrolled.
                toggle?.let {
                    val visibleRight = minOf(width, (if (fits) 0 else scroll.value) + viewportWidth)
                    it.place(visibleRight - it.width - inset, inset)
                }
            }
        }
    }
}

private val CommentBody.Table.Alignment.textAlign
    get() = when (this) {
        CommentBody.Table.Alignment.Leading -> TextAlign.Start
        CommentBody.Table.Alignment.Center -> TextAlign.Center
        CommentBody.Table.Alignment.Trailing -> TextAlign.End
    }
