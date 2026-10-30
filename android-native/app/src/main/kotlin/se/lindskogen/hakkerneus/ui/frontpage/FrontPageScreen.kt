package se.lindskogen.hakkerneus.ui.frontpage

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
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.copyToClipboard
import se.lindskogen.hakkerneus.ui.openInBrowser
import se.lindskogen.hakkerneus.ui.share
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette

/** The front page (`NewsList.tsx`). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FrontPageScreen(openComments: (Story) -> Unit, openItem: (Long) -> Unit, signIn: () -> Unit) {
    val model: FrontPageViewModel = viewModel()
    val state by model.state.collectAsStateWithLifecycle()
    val savedEntries by AppContainer.saved.entries.collectAsState()
    val saved = savedEntries.mapTo(HashSet()) { it.story.id }
    val visits by AppContainer.visited.visits.collectAsState()
    val upvoted by AppContainer.session.upvoted.collectAsState()
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = model.restoredIndex, initialFirstVisibleItemScrollOffset = model.restoredOffset)
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
    LaunchedEffect(nearEnd, state.stories.size) { if (nearEnd) model.loadMore() }

    Box(Modifier.fillMaxSize().background(HN.backgroundDark)) {
        // The first row's colour reaches up behind the status bar.
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(Palette.storyBackground(0)))

        when {
            state.stories.isEmpty() && state.isLoading -> SkeletonRows()
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
                    itemsIndexed(state.stories, key = { _, story -> story.id }) { index, story ->
                        visits.size // re-read when visits change
                        StoryRow(
                            story, Palette.storyBackground(index), story.id in saved, actions,
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
private fun SkeletonRows() {
    val sweep by rememberInfiniteTransition(label = "skeleton").animateFloat(
        initialValue = -1f, targetValue = 2f,
        animationSpec = infiniteRepeatable(tween(1400, easing = LinearEasing), RepeatMode.Restart),
        label = "sweep",
    )
    Column(Modifier.fillMaxSize().semantics { contentDescription = "Loading stories" }) {
        Spacer(Modifier.windowInsetsTopHeight(WindowInsets.statusBars))
        for (index in 0 until 10) {
            Box(
                Modifier.fullWidth().height(100.dp).background(Palette.storyBackground(index))
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
