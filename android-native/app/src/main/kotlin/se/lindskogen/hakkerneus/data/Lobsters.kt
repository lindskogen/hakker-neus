package se.lindskogen.hakkerneus.data

import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URI
import java.time.OffsetDateTime

/**
 * lobste.rs items in the app's HN-shaped models, as on iOS. Lobsters identifies stories and
 * comments by short base-36 codes ("cozhtg"); the app keys everything by number, so they become
 * negative numbers, which can't clash with HN's positive IDs.
 */
object Lobsters {
    const val BASE = "https://lobste.rs/"

    fun isLobsters(id: Long) = id < 0

    /** The app's ID for a short ID; null if it isn't base 36. */
    fun id(shortId: String): Long? = shortId.lowercase().toLongOrNull(36)?.let { -it }

    /** The short ID for one of the app's lobste.rs IDs. */
    fun shortId(id: Long): String = (-id).toString(36).padStart(6, '0')

    fun storyUrl(id: Long) = "${BASE}s/${shortId(id)}"
    fun commentUrl(id: Long) = "${BASE}c/${shortId(id)}"
    fun userUrl(name: String) = "$BASE~$name"

    /** The story ID in a lobste.rs story link (`https://lobste.rs/s/cozhtg/title`), if it is one. */
    fun storyId(url: String): Long? {
        val uri = runCatching { URI(url) }.getOrNull() ?: return null
        if (uri.host?.lowercase() != "lobste.rs") return null
        val parts = uri.path.orEmpty().split("/").filter { it.isNotEmpty() }
        return if (parts.size >= 2 && parts[0] == "s") id(parts[1]) else null
    }
}

val Story.isLobsters get() = Lobsters.isLobsters(id)
val Comment.isLobsters get() = Lobsters.isLobsters(id)

/** Reading lobste.rs through its public JSON (no key): the Hottest list, and each story with its whole thread in one request. */
class LobstersApi(private val transport: HttpTransport, private val base: String = Lobsters.BASE) {
    private val json = Json { ignoreUnknownKeys = true }

    /** One page (25 stories) of the Hottest list; pages start at 1. */
    suspend fun hottest(page: Int): List<Story> {
        val path = if (page == 1) "hottest.json" else "page/$page.json"
        return json.decodeFromString<List<StoryJson>>(transport.get(base + path)).mapNotNull { it.story }
    }

    suspend fun item(id: Long): StoryWithComments {
        val story = json.decodeFromString<StoryJson>(transport.get("${base}s/${Lobsters.shortId(id)}.json"))
        return StoryWithComments(story.story ?: throw HttpException(404), tree(story.comments.orEmpty()))
    }

    @Serializable
    private data class StoryJson(
        @SerialName("short_id") val shortId: String,
        @SerialName("created_at") val createdAt: String,
        val title: String,
        val url: String? = null,
        val score: Int = 0,
        @SerialName("comment_count") val commentCount: Int = 0,
        val description: String? = null,
        @SerialName("submitter_user") val submitter: String? = null,
        val comments: List<CommentJson>? = null,
    ) {
        val story: Story?
            get() = Lobsters.id(shortId)?.let { id ->
                Story(id, title, submitter, url?.ifEmpty { null }, description?.ifEmpty { null }, score, commentCount, seconds(createdAt))
            }
    }

    @Serializable
    private data class CommentJson(
        @SerialName("short_id") val shortId: String,
        @SerialName("created_at") val createdAt: String,
        @SerialName("is_deleted") val isDeleted: Boolean = false,
        @SerialName("is_moderated") val isModerated: Boolean = false,
        val comment: String,
        @SerialName("parent_comment") val parent: String? = null,
        @SerialName("commenting_user") val user: String? = null,
    )

    /** Lobsters lists comments flat, in thread order, each naming its parent. */
    private fun tree(flat: List<CommentJson>): List<Comment> {
        val children = flat.groupBy { it.parent }
        fun build(parent: String?): List<Comment> = children[parent].orEmpty().mapNotNull { c ->
            val id = Lobsters.id(c.shortId) ?: return@mapNotNull null
            Comment(
                id, if (c.isDeleted) null else c.user, if (c.isDeleted || c.isModerated) null else c.comment,
                seconds(c.createdAt), build(c.shortId),
            )
        }
        return build(null)
    }

}

/** Seconds since 1970 for lobste.rs's ISO 8601 times. */
private fun seconds(text: String) = runCatching { OffsetDateTime.parse(text).toEpochSecond() }.getOrDefault(0)

/**
 * Sends lobste.rs items (negative IDs) to [LobstersApi] and everything else to HN, so lists, the
 * comments screen, prefetching and offline copies work the same for both.
 */
class SourceRoutingClient(val hn: HnClient, private val lobsters: LobstersApi = LobstersApi(OkHttpTransport())) : HnClient {
    /** Stories from the Hottest list, so rows don't need a request each. */
    private val known = HashMap<Long, Story>()
    private val mutex = Mutex()

    override suspend fun topStoryIds() = hn.topStoryIds()
    override suspend fun newStoryIds() = hn.newStoryIds()

    /** The first four pages of Hottest (100 stories), fetched together. */
    override suspend fun lobstersStoryIds(): List<Long> {
        val stories = coroutineScope { (1..4).map { async { lobsters.hottest(it) } }.awaitAll() }.flatten()
        mutex.withLock { stories.forEach { known[it.id] = it } }
        return stories.map { it.id }.distinct()
    }

    override suspend fun story(id: Long): Story? {
        if (!Lobsters.isLobsters(id)) return hn.story(id)
        mutex.withLock { known[id] }?.let { return it }
        return lobsters.item(id).story
    }

    override suspend fun item(id: Long) = if (Lobsters.isLobsters(id)) lobsters.item(id) else hn.item(id)
}
