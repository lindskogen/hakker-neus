package se.lindskogen.hakkerneus.ui.theme

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import kotlin.math.floor
import kotlin.math.roundToInt

/**
 * The colour of the front page and the accents that go with it, as on iOS. Orange is the
 * original; blue and green use d3's Blues and Greens the same way. The saved list has its own
 * ramp ([savedStops]): d3's Reds with orange, and darker blues and greens with the others.
 */
enum class ColorTheme(val title: String, internal val stops: IntArray, internal val savedStops: IntArray) {
    Orange(
        "Orange",
        intArrayOf(0xFFF5EB, 0xFEE6CE, 0xFDD0A2, 0xFDAE6B, 0xFD8D3C, 0xF16913, 0xD94801, 0xA63603, 0x7F2704),
        intArrayOf(0xFFF5F0, 0xFEE0D2, 0xFCBBA1, 0xFC9272, 0xFB6A4A, 0xEF3B2C, 0xCB181D, 0xA50F15, 0x67000D), // d3's Reds
    ),
    Blue(
        "Blue",
        intArrayOf(0xF7FBFF, 0xDEEBF7, 0xC6DBEF, 0x9ECAE1, 0x6BAED6, 0x4292C6, 0x2171B5, 0x08519C, 0x08306B),
        intArrayOf(0xF7FBFF, 0xDEEBF7, 0xC6DBEF, 0x9ECAE1, 0x4A90C8, 0x2166AC, 0x0F4C8C, 0x0A3466, 0x061E40), // toward navy
    ),
    Green(
        "Green",
        intArrayOf(0xF7FCF5, 0xE5F5E0, 0xC7E9C0, 0xA1D99B, 0x74C476, 0x41AB5D, 0x238B45, 0x006D2C, 0x00441B),
        intArrayOf(0xF7FCF5, 0xE5F5E0, 0xC7E9C0, 0xA1D99B, 0x5AAE61, 0x2E8540, 0x1B6B32, 0x0E4F24, 0x063015), // toward forest green
    ),
}

/** Ports of the d3-scale-chromatic schemes the app uses, matching the iOS `Palette`. */
object Palette {
    /** The chosen theme; Compose state, so everything drawn with it follows a change. Set via AppContainer. */
    var theme by mutableStateOf(ColorTheme.Orange)

    data class Rgb(val r: Int, val g: Int, val b: Int) {
        val color: Color get() = Color(r, g, b)
    }

    /** `d3.interpolateOranges(t)`: a uniform B-spline through the 9-class Oranges scheme. */
    fun orangesRgb(t: Double): Rgb = interpolate(oranges, t)

    /** The theme's ramp at [t], like `d3.interpolateOranges(t)` for orange. */
    fun themeRgb(t: Double, theme: ColorTheme = this.theme): Rgb = interpolate(stops(*theme.stops), t)

    /** Background for row [index] of the front page (`getBackgroundColor` in `NewsList.tsx`). */
    fun storyBackground(index: Int): Color = themeRgb(rowPosition(index)).color

    /** The comments header and other accents: the first row's colour. */
    fun accent(theme: ColorTheme = this.theme): Color = themeRgb(0.65, theme).color

    /** Behind a row at the upvote stage of a swipe: blue, or orange when the rows are blue. */
    val upvoteStage: Color get() = Color(tableau10[if (theme == ColorTheme.Blue) 1 else 0])

    /** Background for row [index] of the saved list: the theme's saved ramp, so it's clear which list you're on. */
    fun savedStoryBackground(index: Int): Color = interpolate(stops(*theme.savedStops), rowPosition(index)).color

    /** Background for row [index] of the lobste.rs list: dark reds around lobste.rs's own. */
    fun lobstersBackground(index: Int): Color = interpolate(lobsters, rowPosition(index)).color

    /** The lobste.rs comments header: its first row's colour. */
    val lobstersAccent: Color get() = interpolate(lobsters, 0.65).color

    /** Behind the corner button's reel in Hacker News mode: the theme's darkest shade, almost black (warm with orange). */
    val hnReelTint: Color get() = lerp(Color.Black, themeRgb(1.0).color, 0.22f)

    /** Behind the reel in lobster mode: lobste.rs's darkest red, dimmed to a dark crimson. */
    val lobstersReelTint: Color get() = lerp(Color.Black, interpolate(lobsters, 1.0).color, 0.75f)

    /** Reds darkening through lobste.rs's #AC130D, for the lobste.rs list. */
    private val lobsters = stops(0xFFF0EE, 0xF8CFCB, 0xEC9C95, 0xDB6A61, 0xC63B31, 0xAC130D, 0x8E0F0A, 0x6C0B07, 0x480604)

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
