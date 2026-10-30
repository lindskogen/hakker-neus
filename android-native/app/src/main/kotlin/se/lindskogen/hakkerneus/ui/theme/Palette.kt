package se.lindskogen.hakkerneus.ui.theme

import androidx.compose.ui.graphics.Color
import kotlin.math.floor
import kotlin.math.roundToInt

/** Ports of the d3-scale-chromatic schemes the app uses, matching the iOS `Palette`. */
object Palette {
    data class Rgb(val r: Int, val g: Int, val b: Int) {
        val color: Color get() = Color(r, g, b)
    }

    /** `d3.interpolateOranges(t)`: a uniform B-spline through the 9-class Oranges scheme. */
    fun orangesRgb(t: Double): Rgb = interpolate(oranges, t)

    /** `d3.interpolateReds(t)`, for the saved stories list. */
    fun redsRgb(t: Double): Rgb = interpolate(reds, t)

    /** Background for row [index] of the front page (`getBackgroundColor` in `NewsList.tsx`). */
    fun storyBackground(index: Int): Color = orangesRgb(rowPosition(index)).color

    fun savedStoryBackground(index: Int): Color = redsRgb(rowPosition(index)).color

    /** `d3.schemeTableau10[depth]` for nested comments' left border; depth 0 has none. */
    fun commentDepth(depth: Int): Color =
        if (depth == 0) Color.Transparent else Color(tableau10[depth % tableau10.size])

    val tableau10 = longArrayOf(
        0xFF4E79A7, 0xFFF28E2C, 0xFFE15759, 0xFF76B7B2, 0xFF59A14F,
        0xFFEDC949, 0xFFAF7AA1, 0xFFFF9DA7, 0xFF9C755F, 0xFFBAB0AB,
    )

    private fun rowPosition(index: Int) = index / 50.0 * 0.35 + 0.65

    private val oranges = stops(
        0xFFF5EB, 0xFEE6CE, 0xFDD0A2, 0xFDAE6B, 0xFD8D3C, 0xF16913, 0xD94801, 0xA63603, 0x7F2704,
    )
    private val reds = stops(
        0xFFF5F0, 0xFEE0D2, 0xFCBBA1, 0xFC9272, 0xFB6A4A, 0xEF3B2C, 0xCB181D, 0xA50F15, 0x67000D,
    )

    private fun stops(vararg colors: Int) = colors.map {
        Triple((it shr 16 and 0xFF).toDouble(), (it shr 8 and 0xFF).toDouble(), (it and 0xFF).toDouble())
    }

    private fun interpolate(stops: List<Triple<Double, Double, Double>>, t: Double) = Rgb(
        channel(basis(stops.map { it.first }, t)),
        channel(basis(stops.map { it.second }, t)),
        channel(basis(stops.map { it.third }, t)),
    )

    /** Same algorithm as d3-interpolate's `basis`. */
    private fun basis(values: List<Double>, tIn: Double): Double {
        val n = values.size - 1
        val t = tIn.coerceIn(0.0, 1.0)
        val i = if (t >= 1) n - 1 else floor(t * n).toInt()
        val v1 = values[i]
        val v2 = values[i + 1]
        val v0 = if (i > 0) values[i - 1] else 2 * v1 - v2
        val v3 = if (i < n - 1) values[i + 2] else 2 * v2 - v1
        val t1 = (t - i.toDouble() / n) * n
        val t2 = t1 * t1
        val t3 = t2 * t1
        return ((1 - 3 * t1 + 3 * t2 - t3) * v0 +
            (4 - 6 * t2 + 3 * t3) * v1 +
            (1 + 3 * t1 + 3 * t2 - 3 * t3) * v2 +
            t3 * v3) / 6
    }

    private fun channel(value: Double) = value.roundToInt().coerceIn(0, 255)
}
