package se.lindskogen.hakkerneus.ui.comments

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.CommentThread
import kotlinx.coroutines.flow.drop
import se.lindskogen.hakkerneus.data.Comment
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.StoryWithComments
import se.lindskogen.hakkerneus.data.flattened
import se.lindskogen.hakkerneus.html.CommentBody

data class CommentsState(
    val story: Story? = null,
    val storyBody: CommentBody? = null,
    val thread: CommentThread = CommentThread(emptyList()),
    val bodies: Map<Long, CommentBody> = emptyMap(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val error: String? = null,
    /** A comment to scroll to once loaded (after following a link to it). */
    val focusCommentId: Long? = null,
    /** Set when showing a saved copy because loading failed: when it was saved (seconds). */
    val offlineCopyFrom: Long? = null,
)

class CommentsViewModel(private var id: Long) : ViewModel() {
    private val _state = MutableStateFlow(CommentsState(story = AppContainer.knownStories[id]))
    val state: StateFlow<CommentsState> = _state

    /** The thread as last loaded, before local replies are merged in. */
    private var serverResult: StoryWithComments? = null

    init {
        load()
        // Comments posted from the app show up straight away, until Algolia has them.
        viewModelScope.launch {
            AppContainer.localReplies.drop(1).collect { replies ->
                val result = serverResult ?: return@collect
                rebuild(result, offlineFrom = _state.value.offlineCopyFrom, focus = replies.lastOrNull { it.storyId == id }?.comment?.id)
            }
        }
        // Whether the user already upvoted this story, from HN.
        viewModelScope.launch {
            val session = AppContainer.session
            if (!session.isSignedIn) return@launch
            val upvoted = runCatching { session.isUpvotedOnHn(id) }.getOrNull() ?: return@launch
            if (upvoted != id in session.upvoted.value) session.setLocalVote(id, upvoted, counted = true)
        }
    }

    val storyId: Long get() = id

    private suspend fun rebuild(result: StoryWithComments, offlineFrom: Long?, focus: Long? = null) {
        val local = AppContainer.localReplies.value.filter { it.storyId == result.story.id }
        val flat = mergeLocalReplies(local, result.comments, result.story.id).flattened()
        // Parsing every comment's HTML can take a moment on big threads.
        val bodies = withContext(Dispatchers.Default) { flat.associate { it.id to CommentBody.parse(it.comment.text ?: "") } }
        _state.update { current ->
            val target = focus ?: current.focusCommentId
            var thread = CommentThread(flat, current.thread.collapsed)
            target?.let { thread = thread.expandingAncestors(it) }
            current.copy(
                story = result.story,
                storyBody = result.story.text?.let(CommentBody::parse),
                thread = thread,
                bodies = bodies,
                isLoading = false,
                isRefreshing = false,
                error = null,
                offlineCopyFrom = offlineFrom,
                focusCommentId = target,
            )
        }
    }

    fun refresh() {
        _state.update { it.copy(isRefreshing = true) }
        load()
    }

    fun toggleCollapsed(commentId: Long) = _state.update { it.copy(thread = it.thread.toggled(commentId)) }

    fun focusHandled() = _state.update { it.copy(focusCommentId = null) }

    private fun load() {
        viewModelScope.launch {
            try {
                var offlineFrom: Long? = null
                suspend fun fetch(itemId: Long) = try {
                    AppContainer.client.item(itemId).also { if (it.parentStoryId == null) AppContainer.offline.save(itemId, it) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    // No network: the copy saved the last time this thread loaded.
                    val saved = withContext(Dispatchers.IO) { AppContainer.offline.item(itemId) } ?: throw e
                    offlineFrom = saved.second
                    saved.first
                }
                var result = fetch(id)
                result.parentStoryId?.let { storyId ->
                    // A link to a comment: show its story, focused on the comment.
                    _state.update { it.copy(focusCommentId = id) }
                    id = storyId
                    result = fetch(storyId)
                }
                serverResult = result
                rebuild(result, offlineFrom)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Keep what's showing if a refresh fails.
                _state.update {
                    it.copy(isLoading = false, isRefreshing = false, error = if (it.thread.comments.isEmpty()) e.message ?: "Couldn't load comments." else null)
                }
            }
        }
    }
}

/**
 * Inserts local replies under their parents (newest first, as on HN), or at the top for comments
 * on the story, unless the server's thread already has them (same ID, or same author and text).
 */
fun mergeLocalReplies(local: List<AppContainer.LocalReply>, comments: List<Comment>, storyId: Long): List<Comment> {
    fun contains(list: List<Comment>, reply: Comment): Boolean {
        val text = CommentBody.parse(reply.text ?: "").plainText
        return list.any {
            it.id == reply.id || (it.author == reply.author && CommentBody.parse(it.text ?: "").plainText == text) || contains(it.children, reply)
        }
    }
    fun insert(list: List<Comment>, reply: Comment, parent: Long): List<Comment> = list.map {
        it.copy(children = if (it.id == parent) listOf(reply) + it.children else insert(it.children, reply, parent))
    }
    var merged = comments
    for (reply in local) {
        if (contains(merged, reply.comment)) continue
        merged = if (reply.parentId == storyId) listOf(reply.comment) + merged else insert(merged, reply.comment, reply.parentId)
    }
    return merged
}
