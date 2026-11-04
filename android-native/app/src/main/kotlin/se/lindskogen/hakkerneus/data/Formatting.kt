package se.lindskogen.hakkerneus.data

import java.net.URI
import kotlin.math.abs
import kotlin.math.roundToLong

/** Port of date-fns `formatDistanceStrict`, as the RN and iOS apps show ages: "5 hours". */
object RelativeTime {
    fun format(epochSeconds: Long, nowSeconds: Long = System.currentTimeMillis() / 1000): String {
        val seconds = abs(nowSeconds - epochSeconds).toDouble()
        val minutes = seconds / 60
        val (value, unit) = when {
            minutes < 1 -> seconds to "second"
            minutes < 60 -> minutes to "minute"
            minutes < 60 * 24 -> minutes / 60 to "hour"
            minutes < 60 * 24 * 30 -> minutes / (60 * 24) to "day"
            minutes < 60 * 24 * 365 -> minutes / (60 * 24 * 30) to "month"
            else -> minutes / (60 * 24 * 365) to "year"
        }
        val count = value.roundToLong()
        return if (count == 1L) "1 $unit" else "$count ${unit}s"
    }
}

/** A Hacker News link the app can show itself. */
sealed interface HackerNewsLink {
    data class Item(val id: Long) : HackerNewsLink
    data class User(val name: String) : HackerNewsLink

    companion object {
        private val hosts = setOf("news.ycombinator.com", "ycombinator.com", "www.ycombinator.com")

        fun parse(url: String): HackerNewsLink? {
            // lobste.rs story links open in the app too.
            Lobsters.storyId(url)?.let { return Item(it) }
            val uri = runCatching { URI(url) }.getOrNull() ?: return null
            if (uri.host?.lowercase() !in hosts) return null
            val id = uri.rawQuery?.split("&")
                ?.map { it.split("=", limit = 2) }
                ?.firstOrNull { it.first() == "id" }
                ?.getOrNull(1)
                ?.takeIf { it.isNotEmpty() } ?: return null
            return when (uri.path) {
                "/item" -> id.toLongOrNull()?.let { Item(it) }
                "/user" -> User(id)
                else -> null
            }
        }
    }
}
