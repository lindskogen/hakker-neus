package se.lindskogen.hakkerneus.ui.search

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.ui.copyToClipboard
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.ui.share
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.TextTabs
import se.lindskogen.hakkerneus.ui.frontpage.StoryRow
import se.lindskogen.hakkerneus.ui.frontpage.StoryRowActions
import se.lindskogen.hakkerneus.ui.theme.HN

enum class SearchOrder(val title: String) { Relevance("Relevant"), Date("Newest") }

data class SearchState(
    val query: String = "",
    val order: SearchOrder = SearchOrder.Relevance,
    val stories: List<Story> = emptyList(),
    val loading: Boolean = false,
    val error: String? = null,
    val hasMore: Boolean = false,
    /** The query the results are for (empty before the first search). */
    val searched: String = "",
)

/** Story search through HN Search by Algolia, as on iOS. */
class SearchViewModel : ViewModel() {
    private val _state = MutableStateFlow(SearchState())
    val state = _state.asStateFlow()
    private var job: Job? = null
    private var nextPage = 0

    fun type(query: String) {
        _state.update { it.copy(query = query) }
        search(debounce = true)
    }

    fun order(order: SearchOrder) {
        _state.update { it.copy(order = order) }
        search(debounce = false)
    }

    /** Searches for what's typed, after a pause in typing ([debounce]) or straight away. */
    fun search(debounce: Boolean) {
        job?.cancel()
        val query = _state.value.query.trim()
        if (query.isEmpty()) {
            _state.update { it.copy(stories = emptyList(), loading = false, error = null, hasMore = false, searched = "") }
            return
        }
        val order = _state.value.order
        job = viewModelScope.launch {
            if (debounce) delay(300)
            _state.update { it.copy(loading = true, error = null) }
            try {
                val page = AppContainer.users.api.searchStories(query, order == SearchOrder.Date, 0)
                nextPage = 1
                _state.update { it.copy(stories = page.items, loading = false, hasMore = page.hasMore, searched = query) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                _state.update { it.copy(stories = emptyList(), loading = false, error = e.message ?: "Search failed.", searched = query) }
            }
        }
    }

    fun loadMore() {
        val current = _state.value
        if (job?.isActive == true || !current.hasMore || current.searched.isEmpty()) return
        val page = nextPage
        job = viewModelScope.launch {
            _state.update { it.copy(loading = true) }
            try {
                val result = AppContainer.users.api.searchStories(current.searched, current.order == SearchOrder.Date, page)
                nextPage = page + 1
                // Algolia can list a story on two pages when new ones arrive between requests.
                _state.update { state ->
                    val seen = state.stories.mapTo(HashSet()) { it.id }
                    state.copy(stories = state.stories + result.items.filter { seen.add(it.id) }, loading = false, hasMore = result.hasMore)
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // Retried the next time the end of the list comes into view.
                _state.update { it.copy(loading = false) }
            }
        }
    }
}

/** A search field, Relevant / Newest tabs, and the results as quiet rows like on user pages. */
@Composable
fun SearchScreen(
    openComments: (Story) -> Unit, openLink: (String) -> Unit, signIn: () -> Unit,
    scrollToTop: se.lindskogen.hakkerneus.ui.ScrollToTop? = null,
) {
    val model: SearchViewModel = viewModel()
    val state by model.state.collectAsStateWithLifecycle()
    val saved by AppContainer.saved.entries.collectAsState()
    val visits by AppContainer.visited.visits.collectAsState()
    val upvoted by AppContainer.session.upvoted.collectAsState()
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val focusManager = LocalFocusManager.current
    val focus = remember { FocusRequester() }
    val listState = rememberLazyListState()
    se.lindskogen.hakkerneus.ui.BindScrollToTop(scrollToTop, listState)
    val actions = remember {
        StoryRowActions(
            open = { story ->
                AppContainer.visited.markOpened(story)
                val url = story.url
                if (url == null) openComments(story) else openLink(url)
            },
            openComments = openComments,
            toggleSaved = { AppContainer.saved.toggle(it) },
            toggleUpvote = { haptics.performHapticFeedback(HapticFeedbackType.Confirm); AppContainer.toggleVote(it, signIn) },
            share = { context.share(it.url ?: it.hackerNewsUrl, it.title) },
            copyLink = { context.copyToClipboard(it.url ?: it.hackerNewsUrl) },
            copyCommentsLink = { context.copyToClipboard(it.hackerNewsUrl) },
        )
    }

    LaunchedEffect(Unit) { if (state.query.isEmpty()) focus.requestFocus() }
    // Load the next page when the end of the list comes into view.
    val nearEnd by remember { derivedStateOf { (listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0) >= state.stories.size - 5 } }
    LaunchedEffect(nearEnd, state.stories.size) { if (nearEnd && state.stories.isNotEmpty()) model.loadMore() }
    // Back to the top for new results.
    LaunchedEffect(state.searched, state.order) { listState.scrollToItem(0) }
    // Dragging the list hides the keyboard.
    LaunchedEffect(listState) { snapshotFlow { listState.isScrollInProgress }.collect { if (it) focusManager.clearFocus() } }

    Column(Modifier.fillMaxSize().background(HN.backgroundDark).statusBarsPadding()) {
        Row(
            Modifier
                .padding(HN.padding)
                .fillMaxWidth()
                .background(Color.White.copy(alpha = 0.1f), RoundedCornerShape(10.dp))
                .padding(horizontal = 10.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(HnIcons.search, contentDescription = null, tint = Color.White.copy(alpha = 0.5f), modifier = Modifier.size(20.dp))
            Box(Modifier.weight(1f)) {
                if (state.query.isEmpty()) {
                    Text("Search Hacker News", style = HN.body.copy(fontSize = 17.sp, color = Color.White.copy(alpha = 0.4f)))
                }
                BasicTextField(
                    state.query,
                    onValueChange = model::type,
                    singleLine = true,
                    textStyle = HN.body.copy(fontSize = 17.sp),
                    cursorBrush = SolidColor(HN.accent),
                    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search, autoCorrectEnabled = false),
                    keyboardActions = KeyboardActions(onSearch = { focusManager.clearFocus(); model.search(debounce = false) }),
                    modifier = Modifier.fillMaxWidth().focusRequester(focus),
                )
            }
            if (state.query.isNotEmpty()) {
                Icon(
                    HnIcons.close, contentDescription = "Clear", tint = Color.White.copy(alpha = 0.5f),
                    modifier = Modifier.size(20.dp).clickable(onClickLabel = "Clear") { model.type(""); focus.requestFocus() },
                )
            }
        }
        TextTabs(SearchOrder.entries.map { it.title }, state.order.ordinal, onSelect = { model.order(SearchOrder.entries[it]) })

        Box(Modifier.fillMaxSize()) {
            val message = when {
                state.query.isBlank() -> "Search stories on Hacker News."
                state.error != null -> state.error
                !state.loading && state.searched.isNotEmpty() && state.stories.isEmpty() -> "No stories match “${state.searched}”."
                else -> null
            }
            when {
                message != null && state.stories.isEmpty() -> Text(
                    message,
                    style = HN.titleStyle().copy(fontSize = 22.sp, color = Color.White.copy(alpha = 0.3f), textAlign = TextAlign.Center),
                    modifier = Modifier.align(Alignment.Center).padding(20.dp),
                )
                state.loading && state.stories.isEmpty() -> CircularProgressIndicator(color = Color.White, modifier = Modifier.align(Alignment.Center))
                else -> LazyColumn(state = listState, modifier = Modifier.fillMaxSize()) {
                    items(state.stories, key = { it.id }) { story ->
                        visits.size // re-read when visits change
                        StoryRow(
                            story, HN.backgroundDark, saved.any { it.story.id == story.id }, actions,
                            isVisited = AppContainer.visited.isVisited(story.id),
                            isUpvoted = story.id in upvoted,
                            score = AppContainer.session.displayedScore(story.id, story.score),
                            compact = true,
                        )
                        HorizontalDivider(thickness = 0.5.dp, color = Color.Black)
                    }
                    if (state.hasMore) {
                        item {
                            Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(color = Color.White)
                            }
                        }
                    }
                }
            }
        }
    }
}
