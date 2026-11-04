package se.lindskogen.hakkerneus.data

import kotlinx.serialization.Serializable

/** A top-level HN item shown in the story list. [time] is seconds since 1970. */
@Serializable
data class Story(
    val id: Long,
    val title: String,
    val author: String? = null,
    val url: String? = null,
    /** Body HTML for self posts (Ask HN etc). */
    val text: String? = null,
    val score: Int = 0,
    val commentCount: Int = 0,
    val time: Long = 0,
) {
    /** The discussion's page: on HN, or lobste.rs for its stories. */
    val hackerNewsUrl: String get() = if (Lobsters.isLobsters(id)) Lobsters.storyUrl(id) else hackerNewsItemUrl(id)

    /** The linked site, e.g. "github.com", without a leading "www.". Null for self posts. */
    val displayDomain: String?
        get() {
            val host = url?.let { runCatching { java.net.URI(it).host }.getOrNull() } ?: return null
            return host.removePrefix("www.").takeIf { it.isNotEmpty() }
        }
}

/** A comment and its replies. [text] is HN's HTML and is null for deleted comments. */
@Serializable
data class Comment(
    val id: Long,
    val author: String? = null,
    val text: String? = null,
    val time: Long = 0,
    val children: List<Comment> = emptyList(),
) {
    val hackerNewsUrl: String get() = if (Lobsters.isLobsters(id)) Lobsters.commentUrl(id) else hackerNewsItemUrl(id)
}

/** A comment placed in a flat list, with its nesting depth. */
data class FlatComment(val comment: Comment, val depth: Int) {
    val id: Long get() = comment.id
}

/** An item with its comment tree. [parentStoryId] is set when the item is itself a comment. */
@Serializable
data class StoryWithComments(
    val story: Story,
    val comments: List<Comment>,
    val parentStoryId: Long? = null,
)

fun hackerNewsItemUrl(id: Long) = "https://news.ycombinator.com/item?id=$id"
