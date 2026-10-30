package se.lindskogen.hakkerneus

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import se.lindskogen.hakkerneus.data.HackerNewsLink
import se.lindskogen.hakkerneus.data.RelativeTime
import se.lindskogen.hakkerneus.data.Story

class FormattingTest {
    @Test
    fun relativeTimeMatchesDateFns() {
        val now = 1_000_000_000L
        val cases = mapOf(0L to "0 seconds", 1L to "1 second", 90L to "2 minutes", 5 * 3600L to "5 hours", 86400L to "1 day", 30 * 86400L to "1 month", 365 * 86400L to "1 year")
        for ((ago, expected) in cases) assertEquals(expected, RelativeTime.format(now - ago, now))
    }

    @Test
    fun hackerNewsLinks() {
        assertEquals(HackerNewsLink.Item(2192629), HackerNewsLink.parse("https://news.ycombinator.com/item?id=2192629"))
        assertEquals(HackerNewsLink.User("pg"), HackerNewsLink.parse("https://news.ycombinator.com/user?id=pg"))
        assertNull(HackerNewsLink.parse("https://news.ycombinator.com/newest"))
        assertNull(HackerNewsLink.parse("https://notnews.ycombinator.com.evil.com/item?id=1"))
    }

    @Test
    fun displayDomain() {
        assertEquals("example.com", Story(1, "t", url = "https://www.example.com/a").displayDomain)
        assertNull(Story(1, "t").displayDomain)
    }
}
