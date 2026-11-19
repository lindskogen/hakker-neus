package se.lindskogen.hakkerneus.ui.comments

/**
 * Column widths that fit [width]: natural widths if everything fits, else each column's longest
 * word plus a share of the rest in proportion to how much more it would like. Same as iOS.
 */
internal fun fittedWidths(natural: List<Int>, minimum: List<Int>, width: Int): List<Int> {
    val least = minimum.sum()
    val widths = when {
        natural.sum() <= width -> natural.map { it.toDouble() }
        // Even the longest words don't fit: those break too.
        least >= width -> minimum.map { it.toDouble() }
        else -> {
            val wanted = natural.zip(minimum) { n, m -> maxOf(0, n - m) }
            val share = (width - least).toDouble() / maxOf(wanted.sum(), 1)
            minimum.zip(wanted) { m, w -> m + w * share }
        }
    }
    // Scale to exactly the width, giving rounding leftovers to the last column.
    val sum = widths.sum().coerceAtLeast(1.0)
    val scaled = widths.map { (it / sum * width).toInt() }
    return scaled.dropLast(1) + (width - scaled.dropLast(1).sum())
}
