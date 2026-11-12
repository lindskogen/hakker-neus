package se.lindskogen.hakkerneus.ui.user

import androidx.compose.foundation.lazy.LazyListState
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.HnUser
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.UserComment
import se.lindskogen.hakkerneus.html.CommentBody

enum class UserTab(val title: String) { Stories("Stories"), Comments("Comments") }

data class UserState(
    val user: HnUser? = null,
    val about: CommentBody? = null,
    val error: String? = null,
    val tab: UserTab = UserTab.Stories,
    val stories: List<Story> = emptyList(),
    val comments: List<UserComment> = emptyList(),
    val bodies: Map<Long, CommentBody> = emptyMap(),
    /** Next page per tab; absent until the first page has loaded. */
    val nextPage: Map<UserTab, Int> = emptyMap(),
    val hasMore: Map<UserTab, Boolean> = emptyMap(),
    val isLoadingMore: Boolean = false,
) {
    /** Loaded everything there is for the tab and found nothing. */
    val isEmpty: Boolean get() = nextPage[tab] != null && hasMore[tab] == false &&
        (if (tab == UserTab.Stories) stories.isEmpty() else comments.isEmpty())
}

/** An HN user's page, as on iOS: profile, then their stories or comments, paged as you scroll. */
class UserViewModel(private val name: String) : ViewModel() {
    /** Kept here rather than in the screen, so going forward to it again (see Forward.kt) comes back to the same place. */
    val listState = LazyListState()
    private val _state = MutableStateFlow(UserState())
    val state: StateFlow<UserState> = _state
    private var loadJob: Job? = null

    init {
        val preloaded = AppContainer.users.peekFirstPage(name)
        if (preloaded != null) {
            // Already loaded before the screen opened: shown in the first frame.
            val (user, stories) = preloaded
            stories?.items?.forEach { AppContainer.knownStories[it.id] = it }
            _state.value = UserState(
                user = user,
                about = user.about?.let(CommentBody::parse),
                stories = stories?.items.orEmpty(),
                nextPage = if (stories != null) mapOf(UserTab.Stories to 1) else emptyMap(),
                hasMore = if (stories != null) mapOf(UserTab.Stories to stories.hasMore) else emptyMap(),
            )
            if (stories == null) loadMore()
        } else {
            loadProfile()
        }
    }

    private fun loadProfile() {
        viewModelScope.launch {
            try {
                val user = AppContainer.users.user(name)
                val about = user.about?.let { withContext(Dispatchers.Default) { CommentBody.parse(it) } }
                _state.update { it.copy(user = user, about = about) }
                loadMore()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(error = e.message ?: "Couldn't load $name.") }
            }
        }
    }

    fun select(tab: UserTab) {
        if (tab == _state.value.tab) return
        loadJob?.cancel()
        loadJob = null
        _state.update { it.copy(tab = tab, isLoadingMore = false) }
        loadMore()
    }

    fun loadMore() {
        val current = _state.value
        val tab = current.tab
        if (loadJob != null || current.user == null || current.hasMore[tab] == false) return
        val page = current.nextPage[tab] ?: 0
        _state.update { it.copy(isLoadingMore = true) }
        loadJob = viewModelScope.launch {
            try {
                when (tab) {
                    UserTab.Stories -> {
                        val result = AppContainer.users.stories(name, page)
                        result.items.forEach { AppContainer.knownStories[it.id] = it }
                        _state.update { s ->
                            val known = s.stories.mapTo(HashSet()) { it.id }
                            s.copy(stories = s.stories + result.items.filter { it.id !in known }, hasMore = s.hasMore + (tab to result.hasMore))
                        }
                    }
                    UserTab.Comments -> {
                        val result = AppContainer.users.comments(name, page)
                        val bodies = withContext(Dispatchers.Default) { result.items.associate { it.id to CommentBody.parse(it.text) } }
                        _state.update { s ->
                            val known = s.comments.mapTo(HashSet()) { it.id }
                            s.copy(
                                comments = s.comments + result.items.filter { it.id !in known },
                                bodies = s.bodies + bodies,
                                hasMore = s.hasMore + (tab to result.hasMore),
                            )
                        }
                    }
                }
                _state.update { it.copy(nextPage = it.nextPage + (tab to page + 1)) }
            } catch (e: CancellationException) {
                throw e
            } catch (_: Exception) {
                // Scrolling to the end again retries.
            } finally {
                _state.update { it.copy(isLoadingMore = false) }
                loadJob = null
            }
        }
    }
}
