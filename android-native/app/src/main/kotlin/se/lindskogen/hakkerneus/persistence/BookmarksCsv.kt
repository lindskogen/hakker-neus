package se.lindskogen.hakkerneus.persistence

import se.lindskogen.hakkerneus.data.Story
import java.time.Instant
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter

/** RFC 4180 CSV: quoted fields may contain commas, doubled quotes and line breaks. */
object Csv {
    fun parse(text: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val field = StringBuilder()
        var inQuotes = false
        var i = 0
        fun endField() { row += field.toString(); field.clear() }
        fun endRow() {
            endField()
            if (!(row.size == 1 && row[0].isEmpty())) rows += row
            row = mutableListOf()
        }
        while (i < text.length) {
            val c = text[i]
            if (inQuotes) {
                if (c == '"') {
                    if (i + 1 < text.length && text[i + 1] == '"') { field.append('"'); i++ } else inQuotes = false
                } else field.append(c)
            } else when (c) {
                '"' -> inQuotes = true
                ',' -> endField()
                '\r' -> { if (i + 1 < text.length && text[i + 1] == '\n') i++; endRow() }
                '\n' -> endRow()
                else -> field.append(c)
            }
            i++
        }
        if (field.isNotEmpty() || row.isNotEmpty()) endRow()
        return rows
    }

    fun format(rows: List<List<String>>): String = rows.joinToString("\r\n", postfix = "\r\n") { row ->
        row.joinToString(",") { f -> if (f.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) "\"" + f.replace("\"", "\"\"") + "\"" else f }
    }
}

/** The hacker-feed bookmarks format, used for import and export (same as the iOS app). */
object BookmarksCsv {
    private val columns = listOf("id", "title", "url", "hn_url", "domain", "type", "user", "points", "comments", "posted_at", "saved_at", "text", "image_url")

    data class Result(val entries: List<SavedStoriesStore.Entry>, val skipped: Int)

    fun read(text: String): Result {
        val rows = Csv.parse(text).toMutableList()
        if (rows.isEmpty()) return Result(emptyList(), 0)
        val index = rows.removeAt(0).withIndex().associate { (i, name) -> name.trim().lowercase() to i }
        var skipped = 0
        val entries = rows.mapNotNull { row ->
            fun value(column: String) = index[column]?.let { row.getOrNull(it) }?.takeIf { it.isNotEmpty() }
            val id = value("id")?.toLongOrNull()
            val title = value("title")
            if (id == null || title == null) { skipped++; return@mapNotNull null }
            val posted = value("posted_at")?.let(::parseDate) ?: 0.0
            val story = Story(
                id, title, value("user"), value("url"), value("text"),
                value("points")?.toIntOrNull() ?: 0, value("comments")?.toIntOrNull() ?: 0, posted.toLong(),
            )
            SavedStoriesStore.Entry(story, value("saved_at")?.let(::parseDate) ?: posted)
        }
        return Result(entries, skipped)
    }

    fun write(entries: List<SavedStoriesStore.Entry>): String = Csv.format(listOf(columns) + entries.map { entry ->
        val s = entry.story
        listOf(
            s.id.toString(), s.title, s.url ?: "", s.hackerNewsUrl, s.displayDomain ?: "", if (s.url == null) "ask" else "link",
            s.author ?: "", s.score.toString(), s.commentCount.toString(),
            OffsetDateTime.ofInstant(Instant.ofEpochSecond(s.time), ZoneOffset.UTC).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            OffsetDateTime.ofInstant(Instant.ofEpochMilli((entry.savedAt * 1000).toLong()), ZoneOffset.UTC).format(DateTimeFormatter.ISO_OFFSET_DATE_TIME),
            s.text ?: "", "",
        )
    })

    /** ISO 8601 with an offset, any number of fractional digits. Seconds since 1970. */
    fun parseDate(text: String): Double? = runCatching {
        val instant = OffsetDateTime.parse(text).toInstant()
        instant.epochSecond + instant.nano / 1e9
    }.getOrNull()
}
