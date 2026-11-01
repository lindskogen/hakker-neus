package se.lindskogen.hakkerneus.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.net.URLEncoder

/** An HN user's profile, from the official API. [about] is HN's HTML. */
data class HnUser(val id: String, val karma: Int, val created: Long, val about: String?)

/** A comment as listed on a user's page: the comment and the story it's on. */
data class UserComment(val id: Long, val text: String, val time: Long, val storyId: Long?, val storyTitle: String?)

/** One page of a user's stories or comments, newest first. */
data class UserActivityPage<T>(val items: List<T>, val hasMore: Boolean)

class UserNotFoundException(name: String) : Exception("There's no user called $name.")

/**
 * User pages, as on iOS: the profile from Firebase, recent stories and comments from Algolia's
 * search (Firebase only lists item IDs, which would mean a request per item).
 */
class UserApi(
    private val transport: HttpTransport = OkHttpTransport(),
    private val firebase: String = "https://hacker-news.firebaseio.com/v0/",
    private val algolia: String = "https://hn.algolia.com/api/v1/",
    private val pageSize: Int = 30,
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun user(name: String): HnUser {
        val user = json.decodeFromString<User?>(transport.get("${firebase}user/${encode(name)}.json")) ?: throw UserNotFoundException(name)
        return HnUser(user.id, user.karma ?: 0, user.created, user.about?.ifEmpty { null })
    }

    suspend fun stories(name: String, page: Int): UserActivityPage<Story> {
        val result = search("story,author_${encode(name)}", byDate = true, page = page)
        return UserActivityPage(result.hits.mapNotNull { it.story() }, result.page + 1 < result.nbPages)
    }

    /** Stories matching [query], best matches first or (with [byDate]) newest first. */
    suspend fun searchStories(query: String, byDate: Boolean, page: Int): UserActivityPage<Story> {
        val result = search("story", query = query, byDate = byDate, page = page)
        return UserActivityPage(result.hits.mapNotNull { it.story() }, result.page + 1 < result.nbPages)
    }

    suspend fun comments(name: String, page: Int): UserActivityPage<UserComment> {
        val result = search("comment,author_${encode(name)}", byDate = true, page = page)
        val comments = result.hits.mapNotNull { hit ->
            UserComment(hit.objectID.toLongOrNull() ?: return@mapNotNull null, hit.commentText ?: return@mapNotNull null, hit.createdAtI, hit.storyId, hit.storyTitle)
        }
        return UserActivityPage(comments, result.page + 1 < result.nbPages)
    }

    private suspend fun search(tags: String, query: String? = null, byDate: Boolean, page: Int): SearchResult {
        val endpoint = if (byDate) "search_by_date" else "search"
        val queryParameter = query?.let { "&query=${encode(it)}" } ?: ""
        return json.decodeFromString(transport.get("$algolia$endpoint?tags=$tags&hitsPerPage=$pageSize&page=$page$queryParameter"))
    }

    private fun encode(text: String) = URLEncoder.encode(text, "UTF-8")

    @Serializable
    private data class User(val id: String, val karma: Int? = null, val created: Long, val about: String? = null)

    @Serializable
    private data class SearchResult(val hits: List<Hit>, val page: Int, val nbPages: Int)

    @Serializable
    private data class Hit(
        val objectID: String,
        val author: String? = null,
        val title: String? = null,
        val url: String? = null,
        @SerialName("story_text") val storyText: String? = null,
        @SerialName("comment_text") val commentText: String? = null,
        val points: Int? = null,
        @SerialName("num_comments") val numComments: Int? = null,
        @SerialName("story_id") val storyId: Long? = null,
        @SerialName("story_title") val storyTitle: String? = null,
        @SerialName("created_at_i") val createdAtI: Long,
    ) {
        fun story(): Story? {
            val id = objectID.toLongOrNull() ?: return null
            return Story(id, title ?: return null, author, url?.ifEmpty { null }, storyText, points ?: 0, numComments ?: 0, createdAtI)
        }
    }
}
