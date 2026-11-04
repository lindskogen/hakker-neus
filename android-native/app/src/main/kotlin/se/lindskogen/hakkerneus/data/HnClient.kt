package se.lindskogen.hakkerneus.data

import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

interface HnClient {
    /** IDs of the current front page, in rank order (up to 500). */
    suspend fun topStoryIds(): List<Long>

    /** IDs of the newest stories, newest first (up to 500). */
    suspend fun newStoryIds(): List<Long>

    /** A single story, or null if it is deleted, dead or missing. */
    suspend fun story(id: Long): Story?

    /** An item with its full comment tree. */
    suspend fun item(id: Long): StoryWithComments

    /** IDs of lobste.rs's Hottest list, in rank order (see [Lobsters]). Only [SourceRoutingClient] reads lobste.rs. */
    suspend fun lobstersStoryIds(): List<Long> = emptyList()
}

private val json = Json { ignoreUnknownKeys = true }

/** The official HN API: https://github.com/HackerNews/API */
class FirebaseApi(private val transport: HttpTransport, private val base: String = "https://hacker-news.firebaseio.com/v0/") {
    suspend fun topStoryIds(): List<Long> = json.decodeFromString(transport.get("${base}topstories.json"))
    suspend fun newStoryIds(): List<Long> = json.decodeFromString(transport.get("${base}newstories.json"))

    /** Null for deleted, dead or nonexistent items (the API returns `null` for the latter). */
    suspend fun story(id: Long): Story? = json.decodeFromString<Item?>(transport.get("${base}item/$id.json"))?.story

    @Serializable
    private data class Item(
        val id: Long,
        val by: String? = null,
        val title: String? = null,
        val url: String? = null,
        val text: String? = null,
        val score: Int? = null,
        val descendants: Int? = null,
        val time: Long = 0,
        val deleted: Boolean? = null,
        val dead: Boolean? = null,
    ) {
        val story: Story?
            get() {
                if (deleted == true || dead == true || title == null) return null
                return Story(id, title, by, url, text, score ?: 0, descendants ?: 0, time)
            }
    }
}

/** HN Search by Algolia, for comment trees in one request: https://hn.algolia.com/api */
class AlgoliaApi(private val transport: HttpTransport, private val base: String = "https://hn.algolia.com/api/v1/") {
    suspend fun item(id: Long): StoryWithComments = json.decodeFromString<Item>(transport.get("${base}items/$id")).storyWithComments

    @Serializable
    private data class Item(
        val id: Long,
        val type: String? = null,
        @SerialName("story_id") val storyId: Long? = null,
        val author: String? = null,
        val title: String? = null,
        val url: String? = null,
        val text: String? = null,
        val points: Int? = null,
        @SerialName("created_at_i") val createdAt: Long = 0,
        val children: List<Item> = emptyList(),
    ) {
        val comment: Comment get() = Comment(id, author, text, createdAt, children.map { it.comment })

        val storyWithComments: StoryWithComments
            get() {
                val comments = children.map { it.comment }
                // Algolia has no `descendants`; count the comments that have text instead.
                val story = Story(id, title ?: "", author, url, text, points ?: 0, comments.sumOf { it.visibleCount }, createdAt)
                val parent = if (type == "comment" && storyId != id) storyId else null
                return StoryWithComments(story, comments, parent)
            }
    }
}

private val Comment.visibleCount: Int get() = (if (text == null) 0 else 1) + children.sumOf { it.visibleCount }

/** Stories from Firebase, comment trees from Algolia. */
class LiveHnClient(transport: HttpTransport = OkHttpTransport()) : HnClient {
    private val firebase = FirebaseApi(transport)
    private val algolia = AlgoliaApi(transport)

    override suspend fun topStoryIds() = firebase.topStoryIds()
    override suspend fun newStoryIds() = firebase.newStoryIds()
    override suspend fun story(id: Long) = firebase.story(id)

    override suspend fun item(id: Long): StoryWithComments = try {
        algolia.item(id)
    } catch (e: HttpException) {
        if (e.code == 404) throw NotFoundException(id) else throw e
    }
}

/** Fetches stories concurrently, keeping the input order and dropping missing ones. */
suspend fun HnClient.stories(ids: List<Long>): List<Story> = coroutineScope {
    ids.map { async { story(it) } }.mapNotNull { it.await() }
}
