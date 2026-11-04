package se.lindskogen.hakkerneus.ui.frontpage

import se.lindskogen.hakkerneus.data.isLobsters
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import androidx.compose.runtime.snapshotFlow
import kotlinx.coroutines.delay
import androidx.compose.runtime.setValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.animation.fadeOut
import androidx.compose.animation.fadeIn
import androidx.compose.animation.Crossfade
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.fillMaxWidth as fullWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LifecycleEventEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.HackerNewsLink
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.TopStoriesFeed
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.copyToClipboard
import se.lindskogen.hakkerneus.ui.openInBrowser
import se.lindskogen.hakkerneus.ui.share
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette

/**
 * The front page (`NewsList.tsx`), or with [isNew] HN's New list (opened from the front page's
 * New button, filtered by the minimum votes setting).
 */
/** What the corner button's feed menu needs from the feed showing: set by [FrontPageScreen]. */
class FeedMenuHooks {
    var hasRead = false
    var canUndo = false
    var hide: () -> Unit = {}
    var undo: () -> Unit = {}
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FrontPageScreen(
    openComments: (Story) -> Unit, openItem: (Long) -> Unit, signIn: () -> Unit,
    source: TopStoriesFeed.Source = TopStoriesFeed.Source.Top,
    menu: FeedMenuHooks? = null,
) {
    val isNew = source == TopStoriesFeed.Source.New
    val isFront = source == TopStoriesFeed.Source.Top
    val rowBackground: (Int) -> Color = if (source == TopStoriesFeed.Source.Lobsters) Palette::lobstersBackground else Palette::storyBackground
    val model: FrontPageViewModel = viewModel(key = source.name) { FrontPageViewModel(source) }
    val state by model.state.collectAsStateWithLifecycle()
    val savedEntries by AppContainer.saved.entries.collectAsState()
    val saved = savedEntries.mapTo(HashSet()) { it.story.id }
    val visits by AppContainer.visited.visits.collectAsState()
    val upvoted by AppContainer.session.upvoted.collectAsState()
    val hidden by AppContainer.hidden.ids.collectAsState()
    // Stories hidden with the hide-read button stay out of the list.
    val minimumScore = if (isNew) AppContainer.newMinimumScore else 0
    val shown = remember(state.stories, hidden, minimumScore) { state.stories.filter { it.id !in hidden && it.score >= minimumScore } }
    /** What the menu last hid, which it offers to show again. Kept while switching feeds. */
    var justHidden by rememberSaveable { mutableStateOf<List<Long>?>(null) }
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = model.restoredIndex, initialFirstVisibleItemScrollOffset = model.restoredOffset)
    // Switching feeds leaves this one; come back to the same place.
    DisposableEffect(listState) {
        onDispose { model.remember(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) }
    }
    // Remember the list and where it's scrolled when leaving the app, to show it again next launch.
    LifecycleEventEffect(Lifecycle.Event.ON_STOP) { model.saveForNextLaunch(listState.firstVisibleItemIndex, listState.firstVisibleItemScrollOffset) }

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
            toggleUpvote = { haptics.performHapticFeedback(HapticFeedbackType.Confirm); AppContainer.toggleVote(it, signIn) },
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
            isNew && shown.isEmpty() && state.stories.isNotEmpty() && !state.hasMore ->
                Text(
                    "No new stories with $minimumScore or more points yet.",
                    style = HN.titleStyle().copy(color = Color.White.copy(alpha = 0.3f)),
                    modifier = Modifier.align(Alignment.Center).padding(20.dp),
                )
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
                        if (story.isLobsters) LobstersStoryRow(
                            story, rowBackground(index), story.id in saved, actions,
                            isVisited = AppContainer.visited.isVisited(story.id),
                            newComments = AppContainer.visited.newCommentCount(story),
                        ) else StoryRow(
                            story, rowBackground(index), story.id in saved, actions,
                            isVisited = AppContainer.visited.isVisited(story.id),
                            newComments = AppContainer.visited.newCommentCount(story),
                            isUpvoted = story.id in upvoted,
                            score = AppContainer.session.displayedScore(story.id, story.score),
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


        // The corner button's menu hides read stories, and shows them again.
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

@Composable
private fun ErrorState(message: String) {
    Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(HnIcons.error, contentDescription = null, tint = HN.backgroundRed.copy(alpha = 0.5f), modifier = Modifier.size(60.dp))
        Text(message, style = HN.titleStyle().copy(color = Color.White.copy(alpha = 0.3f)), modifier = Modifier.padding(20.dp))
    }
}

/** Placeholder rows while the front page loads, with a highlight sweeping across. */
@Composable
private fun SkeletonRows(rowBackground: (Int) -> Color) {
    val sweep by rememberInfiniteTransition(label = "skeleton").animateFloat(
        initialValue = -1f, targetValue = 2f,
        animationSpec = infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart),
        label = "sweep",
    )
    Column(Modifier.fillMaxSize().semantics { contentDescription = "Loading stories" }) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        for (index in 0 until 10) {
            Box(
                Modifier.fullWidth().height(100.dp).background(rowBackground(index))
                    .background(Brush.linearGradient(
                        listOf(Color.Transparent, Color.White.copy(alpha = 0.12f), Color.Transparent),
                        start = Offset(sweep * 1200f - 400f, 0f), end = Offset(sweep * 1200f + 400f, 400f),
                    )),
            ) {
                Column(Modifier.padding(start = HN.padding, top = 20.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Bar(0.85f, 20)
                    Bar(0.55f + (index % 3) * 0.1f, 20)
                    Spacer(Modifier.height(4.dp))
                    Bar(0.3f, 10)
                }
            }
            HorizontalDivider(thickness = 0.5.dp, color = Color.Black)
        }
    }
}

@Composable
private fun Bar(fraction: Float, height: Int) {
    Box(Modifier.fillMaxWidth(fraction).height(height.dp).clip(RoundedCornerShape((height / 3).dp)).background(Color.White.copy(alpha = 0.22f)))
}
