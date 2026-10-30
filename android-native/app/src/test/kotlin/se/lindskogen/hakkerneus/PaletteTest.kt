package se.lindskogen.hakkerneus

import org.junit.Assert.assertEquals
import org.junit.Test
import se.lindskogen.hakkerneus.ui.theme.Palette
import se.lindskogen.hakkerneus.ui.theme.Palette.Rgb

class PaletteTest {
    /** Expected values from d3-scale-chromatic@2's interpolateOranges, as in the iOS tests. */
    @Test
    fun orangesMatchesD3() {
        val expected = mapOf(
            0.0 to Rgb(255, 245, 235),
            0.3 to Rgb(253, 194, 140),
            0.65 to Rgb(235, 99, 17),
            0.72 to Rgb(221, 81, 7),
            0.9 to Rgb(159, 51, 3),
            1.0 to Rgb(127, 39, 4),
            1.07 to Rgb(127, 39, 4),
        )
        for ((t, rgb) in expected) assertEquals("t=$t", rgb, Palette.orangesRgb(t))
    }
}
