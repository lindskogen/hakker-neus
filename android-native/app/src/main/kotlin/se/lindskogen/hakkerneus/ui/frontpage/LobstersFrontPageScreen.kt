package se.lindskogen.hakkerneus.ui.frontpage

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.HackerNewsLink
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.TopStoriesFeed
import se.lindskogen.hakkerneus.ui.copyToClipboard
import se.lindskogen.hakkerneus.ui.openInBrowser
import se.lindskogen.hakkerneus.ui.share
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette

/**
 * lobste.rs's Hottest or Newest list, in lobster mode: [FrontPageScreen] in lobste.rs's reds,
 * without voting or the minimum score, and not kept between launches.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LobstersFrontPageScreen(
    openComments: (Story) -> Unit, openItem: (Long) -> Unit,
    source: TopStoriesFeed.Source = TopStoriesFeed.Source.LobstersHottest,
    menu: HideReadHooks? = null,
) {
    val rowBackground: (Int) -> Color = Palette::lobstersBackground
    val model: FrontPageViewModel = viewModel(key = source.name) { FrontPageViewModel(source) }
    val state by model.state.collectAsStateWithLifecycle()
    val savedEntries by AppContainer.saved.entries.collectAsState()
    val saved = savedEntries.mapTo(HashSet()) { it.story.id }
    val visits by AppContainer.visited.visits.collectAsState()
    val hidden by AppContainer.hidden.ids.collectAsState()
    // Stories hidden with the hide-read button stay out of the list.
    val shown = remember(state.stories, hidden) { state.stories.filter { it.id !in hidden } }
    /** What the hide-read button last hid, which it offers to show again. */
    var justHidden by rememberSaveable { mutableStateOf<List<Long>?>(null) }
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = model.restoredIndex, initialFirstVisibleItemScrollOffset = model.restoredOffset)
    // Switching feeds leaves this one; come back to the same place.
    DisposableEffect(listState) {
        onDispose { model.remember(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) }
    }

    val actions = remember {
        StoryRowActions(
            open = { story ->
                AppContainer.visited.markOpened(story)
                val url = story.url
                when {
                    url == null -> openComments(story)
                    HackerNewsLink.parse(url) is HackerNewsLink.Item -> openItem((HackerNewsLink.parse(url) as HackerNewsLink.Item).id)
                    else -> context.openInBrowser(url)
                }
            },
            openComments = openComments,
            toggleSaved = { AppContainer.saved.toggle(it) },
            toggleUpvote = {},
            share = { context.share(it.url ?: it.hackerNewsUrl, it.title) },
            copyLink = { context.copyToClipboard(it.url ?: it.hackerNewsUrl) },
            copyCommentsLink = { context.copyToClipboard(it.hackerNewsUrl) },
        )
    }

    // Load more as the end of the list comes into view.
    val nearEnd by remember {
        derivedStateOf {
            val last = listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index ?: 0
            last >= listState.layoutInfo.totalItemsCount - 5
        }
    }
    // Once scrolling stops, the comments of the rows on screen (on unmetered networks).
    LaunchedEffect(listState, shown) {
        snapshotFlow { if (listState.isScrollInProgress) null else listState.layoutInfo.visibleItemsInfo.map { it.key } }
            .filterNotNull()
            .distinctUntilChanged()
            .collect { keys -> AppContainer.prefetchVisible(keys.mapNotNull { key -> shown.find { it.id == key } }) }
    }
    // Hiding can leave too few rows to scroll to the end, where the next page loads.
    LaunchedEffect(nearEnd, state.stories.size, shown.size) { if (nearEnd || (state.stories.isNotEmpty() && shown.size < 15)) model.loadMore() }

    Box(Modifier.fillMaxSize().background(HN.backgroundDark)) {
        // The first row's colour reaches up behind the status bar.
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(rowBackground(0)))

        when {
            state.stories.isEmpty() && state.isLoading -> SkeletonRows(rowBackground)
            state.stories.isEmpty() && state.error != null -> ErrorState(state.error!!)
            else -> PullToRefreshBox(isRefreshing = state.isRefreshing, onRefresh = { haptics.performHapticFeedback(HapticFeedbackType.Confirm); model.refresh() }) {
                LazyColumn(
                    state = listState,
                    contentPadding = PaddingValues(
                        top = WindowInsets.statusBars.asPaddingValues().calculateTopPadding(),
                        bottom = 96.dp,
                    ),
                    modifier = Modifier.fillMaxSize(),
                ) {
                    itemsIndexed(shown, key = { _, story -> story.id }) { index, story ->
                        visits.size // re-read when visits change
                        LobstersStoryRow(
                            story, rowBackground(index), story.id in saved, actions,
                            isVisited = AppContainer.visited.isVisited(story.id),
                            newComments = AppContainer.visited.newCommentCount(story),
                        )
                        HorizontalDivider(thickness = 0.5.dp, color = Color.Black)
                    }
                    if (state.isLoadingMore) {
                        item {
                            Box(Modifier.fillMaxWidth().padding(20.dp), contentAlignment = Alignment.Center) {
                                CircularProgressIndicator(color = Color.White)
                            }
                        }
                    }
                }
            }
        }

        // The hide-read button above the corner button hides read stories, and shows them again.
        visits.size // re-read when visits change
        val hasRead = shown.any { AppContainer.visited.isVisited(it.id) }
        SideEffect {
            menu?.hasRead = hasRead
            menu?.canUndo = justHidden != null
            menu?.hide = {
                val read = shown.map { it.id }.filter { AppContainer.visited.isVisited(it) }
                if (read.isNotEmpty()) {
                    haptics.performHapticFeedback(HapticFeedbackType.Confirm)
                    AppContainer.hidden.hide(read)
                    justHidden = read
                }
            }
            menu?.undo = {
                justHidden?.let { AppContainer.hidden.unhide(it) }
                justHidden = null
            }
        }
    }
}
