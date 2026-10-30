package se.lindskogen.hakkerneus.ui.frontpage

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.TopStoriesFeed

data class FrontPageState(
    val stories: List<Story> = emptyList(),
    val isLoading: Boolean = true,
    val isRefreshing: Boolean = false,
    val isLoadingMore: Boolean = false,
    val error: String? = null,
)

class FrontPageViewModel : ViewModel() {
    private val feed = TopStoriesFeed(AppContainer.client)
    private val _state = MutableStateFlow(FrontPageState())
    val state: StateFlow<FrontPageState> = _state

    init {
        load(refreshing = false)
    }

    fun refresh() = load(refreshing = true)

    private fun load(refreshing: Boolean) {
        _state.update { it.copy(isRefreshing = refreshing, error = null) }
        viewModelScope.launch {
            try {
                show(feed.reload())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Keep what's showing if a refresh fails.
                _state.update { it.copy(isLoading = false, isRefreshing = false, error = e.message ?: "Couldn't load stories.") }
            }
        }
    }

    /** Called as the end of the list comes into view. A failed page is retried next time. */
    fun loadMore() {
        val current = _state.value
        if (current.isLoadingMore || current.stories.isEmpty() || !feed.hasMore) return
        _state.update { it.copy(isLoadingMore = true) }
        viewModelScope.launch {
            val all = runCatching { feed.loadNextPage() }.getOrNull()
            _state.update { it.copy(isLoadingMore = false) }
            all?.let(::show)
        }
    }

    private fun show(stories: List<Story>) {
        stories.forEach { AppContainer.knownStories[it.id] = it }
        _state.update { it.copy(stories = stories, isLoading = false, isRefreshing = false, error = null) }
    }
}
