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
import se.lindskogen.hakkerneus.data.Story
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
)

class CommentsViewModel(private var id: Long) : ViewModel() {
    private val _state = MutableStateFlow(CommentsState(story = AppContainer.knownStories[id]))
    val state: StateFlow<CommentsState> = _state

    init {
        load()
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
                var result = AppContainer.client.item(id)
                result.parentStoryId?.let { storyId ->
                    // A link to a comment: show its story, focused on the comment.
                    _state.update { it.copy(focusCommentId = id) }
                    id = storyId
                    result = AppContainer.client.item(storyId)
                }
                val flat = result.comments.flattened()
                // Parsing every comment's HTML can take a moment on big threads.
                val bodies = withContext(Dispatchers.Default) {
                    flat.associate { it.id to CommentBody.parse(it.comment.text ?: "") }
                }
                _state.update { current ->
                    var thread = CommentThread(flat, current.thread.collapsed)
                    current.focusCommentId?.let { thread = thread.expandingAncestors(it) }
                    current.copy(
                        story = result.story,
                        storyBody = result.story.text?.let(CommentBody::parse),
                        thread = thread,
                        bodies = bodies,
                        isLoading = false,
                        isRefreshing = false,
                        error = null,
                    )
                }
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
