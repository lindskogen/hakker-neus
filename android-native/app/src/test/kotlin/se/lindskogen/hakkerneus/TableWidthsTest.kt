package se.lindskogen.hakkerneus

import org.junit.Assert.assertEquals
import org.junit.Test
import se.lindskogen.hakkerneus.ui.comments.fittedWidths

class TableWidthsTest {
    @Test
    fun naturalWidthsSpreadWhenTheyFit() {
        assertEquals(listOf(100, 200), fittedWidths(natural = listOf(50, 100), minimum = listOf(20, 30), width = 300))
    }

    @Test
    fun longestWordsKeptAndTheRestSharedByHowMuchMoreEachWants() {
        // 300 natural vs 150 room: minimums 20 + 30 = 50, the other 100 split 80:120.
        assertEquals(listOf(60, 90), fittedWidths(natural = listOf(100, 150), minimum = listOf(20, 30), width = 150))
    }

    @Test
    fun wordsTooLongToFitShareByLength() {
        assertEquals(listOf(25, 75), fittedWidths(natural = listOf(200, 600), minimum = listOf(100, 300), width = 100))
    }
}
