package se.lindskogen.hakkerneus.persistence

import android.content.ContentValues
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.StoryWithComments

/** Writes happen off the main thread; reads come from memory, loaded at startup. */
private val io = CoroutineScope(SupervisorJob() + Dispatchers.IO)

private fun now() = System.currentTimeMillis() / 1000.0

/** Stories the user has saved, newest first, whole so the list works offline. */
class SavedStoriesStore(private val db: Database) {
    data class Entry(val story: Story, val savedAt: Double)

    private val _entries = MutableStateFlow(load())
    val entries: StateFlow<List<Entry>> = _entries

    fun isSaved(id: Long) = _entries.value.any { it.story.id == id }

    fun toggle(story: Story) = if (isSaved(story.id)) remove(story.id) else save(story)

    fun save(story: Story, savedAt: Double = now()) {
        val entry = Entry(story, savedAt)
        set(_entries.value.filterNot { it.story.id == story.id } + entry)
        io.launch { insert(entry) }
    }

    fun remove(id: Long) {
        set(_entries.value.filterNot { it.story.id == id })
        io.launch { db.writableDatabase.delete("saved_stories", "id = ?", arrayOf(id.toString())) }
    }

    /** Adds imported stories; ones already saved keep the earlier saved date. Returns (added, alreadySaved). */
    fun merge(imported: List<Entry>): Pair<Int, Int> {
        val byId = _entries.value.associateBy { it.story.id }.toMutableMap()
        var added = 0
        var already = 0
        val changed = mutableListOf<Entry>()
        for (entry in imported) {
            val existing = byId[entry.story.id]
            if (existing != null) {
                already++
                if (entry.savedAt < existing.savedAt) Entry(existing.story, entry.savedAt).also { byId[it.story.id] = it; changed += it }
            } else {
                added++
                byId[entry.story.id] = entry
                changed += entry
            }
        }
        set(byId.values.toList())
        io.launch {
            val w = db.writableDatabase
            w.beginTransaction()
            try { changed.forEach(::insert); w.setTransactionSuccessful() } finally { w.endTransaction() }
        }
        return added to already
    }

    private fun set(entries: List<Entry>) {
        _entries.value = entries.sortedByDescending { it.savedAt }
    }

    private fun insert(entry: Entry) {
        val s = entry.story
        db.writableDatabase.insertWithOnConflict("saved_stories", null, ContentValues().apply {
            put("id", s.id); put("title", s.title); put("author", s.author); put("url", s.url); put("text", s.text)
            put("score", s.score); put("comment_count", s.commentCount); put("posted_at", s.time.toDouble()); put("saved_at", entry.savedAt)
        }, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
    }

    private fun load(): List<Entry> = db.readableDatabase.rawQuery(
        "SELECT id, title, author, url, text, score, comment_count, posted_at, saved_at FROM saved_stories ORDER BY saved_at DESC", null,
    ).use { c ->
        buildList {
            while (c.moveToNext()) {
                val story = Story(
                    c.getLong(0), c.getString(1), c.getStringOrNull(2), c.getStringOrNull(3), c.getStringOrNull(4),
                    c.getInt(5), c.getInt(6), c.getDouble(7).toLong(),
                )
                add(Entry(story, c.getDouble(8)))
            }
        }
    }
}

/** A comment the user saved, with the story it's on, kept whole so the list works offline. [text] is HN's HTML. */
data class SavedComment(
    val id: Long, val author: String?, val text: String, val time: Long,
    val storyId: Long?, val storyTitle: String?, val savedAt: Double,
) {
    val hackerNewsUrl: String get() = se.lindskogen.hakkerneus.data.hackerNewsItemUrl(id)
}

/** Comments the user has saved, newest first, next to the saved stories. */
class SavedCommentsStore(private val db: Database) {
    private val _entries = MutableStateFlow(load())
    val entries: StateFlow<List<SavedComment>> = _entries

    fun isSaved(id: Long) = _entries.value.any { it.id == id }

    fun toggle(comment: se.lindskogen.hakkerneus.data.Comment, story: Story?) =
        if (isSaved(comment.id)) remove(comment.id) else save(comment, story)

    fun save(comment: se.lindskogen.hakkerneus.data.Comment, story: Story?) {
        val text = comment.text ?: return
        val entry = SavedComment(comment.id, comment.author, text, comment.time, story?.id, story?.title, now())
        _entries.value = (listOf(entry) + _entries.value.filterNot { it.id == comment.id })
        io.launch {
            db.writableDatabase.insertWithOnConflict("saved_comments", null, ContentValues().apply {
                put("id", entry.id); put("story_id", entry.storyId); put("story_title", entry.storyTitle); put("author", entry.author)
                put("text", entry.text); put("posted_at", entry.time.toDouble()); put("saved_at", entry.savedAt)
            }, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    fun remove(id: Long) {
        _entries.value = _entries.value.filterNot { it.id == id }
        io.launch { db.writableDatabase.delete("saved_comments", "id = ?", arrayOf(id.toString())) }
    }

    private fun load(): List<SavedComment> = db.readableDatabase.rawQuery(
        "SELECT id, story_id, story_title, author, text, posted_at, saved_at FROM saved_comments ORDER BY saved_at DESC", null,
    ).use { c ->
        buildList {
            while (c.moveToNext()) {
                add(SavedComment(
                    c.getLong(0), c.getStringOrNull(3), c.getString(4), c.getDouble(5).toLong(),
                    if (c.isNull(1)) null else c.getLong(1), c.getStringOrNull(2), c.getDouble(6),
                ))
            }
        }
    }
}

/** Which stories have been opened, and how many comments they had when last opened. */
class VisitedStoriesStore(private val db: Database) {
    data class Visit(val openedAt: Double, val seenCommentCount: Int?)

    private val _visits = MutableStateFlow(load())
    val visits: StateFlow<Map<Long, Visit>> = _visits

    fun isVisited(id: Long) = id in _visits.value

    /** Comments added since the comments were last opened; null if never opened or none are new. */
    fun newCommentCount(story: Story): Int? {
        val seen = _visits.value[story.id]?.seenCommentCount ?: return null
        return (story.commentCount - seen).takeIf { it > 0 }
    }

    fun markOpened(story: Story) = record(story.id, Visit(now(), _visits.value[story.id]?.seenCommentCount))

    fun markCommentsSeen(story: Story) = record(story.id, Visit(now(), story.commentCount))

    private fun record(id: Long, visit: Visit) {
        _visits.value = _visits.value + (id to visit)
        io.launch {
            db.writableDatabase.insertWithOnConflict("visited_stories", null, ContentValues().apply {
                put("id", id); put("opened_at", visit.openedAt); put("seen_comment_count", visit.seenCommentCount)
            }, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    private fun load(): Map<Long, Visit> = db.readableDatabase.rawQuery("SELECT id, opened_at, seen_comment_count FROM visited_stories", null).use { c ->
        buildMap { while (c.moveToNext()) put(c.getLong(0), Visit(c.getDouble(1), if (c.isNull(2)) null else c.getInt(2))) }
    }
}

/** Copies of recently loaded comment threads, for when there's no network. Kept for a week. */
class OfflineItemStore(private val db: Database) {
    private val json = Json { ignoreUnknownKeys = true }
    private val maxAge = 7 * 24 * 3600.0

    init {
        io.launch { db.writableDatabase.delete("item_cache", "fetched_at < ?", arrayOf((now() - maxAge).toString())) }
    }

    fun save(id: Long, item: StoryWithComments) {
        io.launch {
            db.writableDatabase.insertWithOnConflict("item_cache", null, ContentValues().apply {
                put("id", id); put("json", json.encodeToString(StoryWithComments.serializer(), item)); put("fetched_at", now())
            }, android.database.sqlite.SQLiteDatabase.CONFLICT_REPLACE)
        }
    }

    /** The saved copy and when it was fetched (seconds), if there's one younger than a week. Call off the main thread. */
    fun item(id: Long): Pair<StoryWithComments, Long>? = db.readableDatabase.rawQuery(
        "SELECT json, fetched_at FROM item_cache WHERE id = ?", arrayOf(id.toString()),
    ).use { c ->
        if (!c.moveToFirst() || now() - c.getDouble(1) > maxAge) return null
        runCatching { json.decodeFromString(StoryWithComments.serializer(), c.getString(0)) }.getOrNull()?.let { it to c.getDouble(1).toLong() }
    }
}

/**
 * Front-page stories hidden with the hide-read button, as on iOS. They stay hidden across
 * refreshes; only the most recent few thousand are kept.
 */
class HiddenStoriesStore(context: android.content.Context) {
    private val prefs = context.getSharedPreferences("hidden", android.content.Context.MODE_PRIVATE)
    private val limit = 3000
    /** Oldest first. */
    private var order: List<Long> = prefs.getString("ids", "")!!.split(',').mapNotNull { it.toLongOrNull() }

    private val _ids = MutableStateFlow(order.toSet())
    val ids: StateFlow<Set<Long>> = _ids

    fun hide(ids: List<Long>) {
        val current = _ids.value
        order = (order + ids.filter { it !in current }).takeLast(limit)
        save()
    }

    fun unhide(ids: List<Long>) {
        val remove = ids.toSet()
        order = order.filter { it !in remove }
        save()
    }

    private fun save() {
        _ids.value = order.toSet()
        prefs.edit().putString("ids", order.joinToString(",")).apply()
    }
}

private fun android.database.Cursor.getStringOrNull(index: Int): String? = if (isNull(index)) null else getString(index)
