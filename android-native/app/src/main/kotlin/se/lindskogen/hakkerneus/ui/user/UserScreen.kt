package se.lindskogen.hakkerneus.ui.user

import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.background
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.HackerNewsLink
import se.lindskogen.hakkerneus.data.RelativeTime
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.UserComment
import se.lindskogen.hakkerneus.html.CommentBody
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.comments.CommentText
import se.lindskogen.hakkerneus.ui.copyToClipboard
import se.lindskogen.hakkerneus.ui.frontpage.StoryRow
import se.lindskogen.hakkerneus.ui.frontpage.StoryRowActions
import se.lindskogen.hakkerneus.ui.openInBrowser
import se.lindskogen.hakkerneus.ui.share
import se.lindskogen.hakkerneus.ui.theme.HN
import java.text.NumberFormat
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter

/**
 * An HN user's page, as on iOS: karma, when they joined and their about text, then their
 * recent stories or comments, newest first, loading more as you scroll. Stories are rows like
 * on the front page; a comment opens its thread, focused on it.
 */
@Composable
fun UserScreen(
    name: String,
    openComments: (Story) -> Unit,
    openItem: (Long) -> Unit,
    openLink: (String) -> Unit,
    signIn: () -> Unit,
) {
    val model: UserViewModel = viewModel(key = "user-$name") { UserViewModel(name) }
    val state by model.state.collectAsStateWithLifecycle()
    val saved by AppContainer.saved.entries.collectAsState()
    val visits by AppContainer.visited.visits.collectAsState()
    val upvoted by AppContainer.session.upvoted.collectAsState()
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val listState = rememberLazyListState()
    val actions = remember {
        StoryRowActions(
            open = { story ->
                AppContainer.visited.markOpened(story)
                val url = story.url
                when {
                    url == null -> openComments(story)
                    else -> openLink(url)
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

    // Load the next page when the end of the list comes into view.
    LaunchedEffect(listState, state.tab) {
        snapshotFlow { listState.layoutInfo.visibleItemsInfo.lastOrNull()?.index to listState.layoutInfo.totalItemsCount }
            .collect { (last, total) -> if (last != null && last >= total - 5) model.loadMore() }
    }

    Box(Modifier.fillMaxSize().background(HN.backgroundDark)) {
        val user = state.user
        when {
            state.error != null -> Text(
                state.error!!,
                style = HN.titleStyle().copy(fontSize = 24.sp, color = Color.White.copy(alpha = 0.3f)),
                modifier = Modifier.align(Alignment.Center).padding(20.dp),
            )
            user == null -> CircularProgressIndicator(color = Color.White, modifier = Modifier.align(Alignment.Center))
            else -> LazyColumn(state = listState, contentPadding = PaddingValues(bottom = 48.dp), modifier = Modifier.fillMaxSize()) {
                item(key = "profile") {
                    Column(
                        Modifier.fillMaxWidth().statusBarsPadding().padding(start = HN.padding, end = HN.padding, top = 20.dp, bottom = 15.dp),
                        verticalArrangement = Arrangement.spacedBy(4.dp),
                    ) {
                        Text(user.id, style = HN.titleStyle(), modifier = Modifier.semantics { heading() })
                        val joined = DateTimeFormatter.ofPattern("MMMM yyyy").format(Instant.ofEpochSecond(user.created).atZone(ZoneId.systemDefault()))
                        Text(
                            "${NumberFormat.getIntegerInstance().format(user.karma)} karma · joined $joined",
                            style = HN.body.copy(fontSize = 14.sp, color = Color.White.copy(alpha = 0.6f)),
                        )
                        state.about?.takeIf { it.blocks.isNotEmpty() }?.let {
                            Spacer(Modifier.heightIn(min = 6.dp))
                            CommentText(it, openLink)
                        }
                        Spacer(Modifier.heightIn(min = 8.dp))
                        se.lindskogen.hakkerneus.ui.TextTabs(UserTab.entries.map { it.title }, state.tab.ordinal, onSelect = { model.select(UserTab.entries[it]) })
                    }
                }
                when (state.tab) {
                    UserTab.Stories -> itemsIndexed(state.stories, key = { _, story -> "s${story.id}" }) { _, story ->
                        visits.size // re-read when visits change
                        // Quiet rows like the comments tab: the profile is the focus here, not a front page.
                        StoryRow(
                            story, HN.backgroundDark, saved.any { it.story.id == story.id }, actions,
                            isVisited = AppContainer.visited.isVisited(story.id),
                            isUpvoted = story.id in upvoted,
                            score = AppContainer.session.displayedScore(story.id, story.score),
                            compact = true,
                        )
                        HorizontalDivider(thickness = 0.5.dp, color = Color.Black)
                    }
                    UserTab.Comments -> itemsIndexed(state.comments, key = { _, comment -> "c${comment.id}" }) { _, comment ->
                        UserCommentRow(comment, state.bodies[comment.id], openItem = openItem, onLink = openLink)
                    }
                }
                item(key = "footer-${state.tab}") {
                    Box(Modifier.fillMaxWidth().heightIn(min = 60.dp), contentAlignment = Alignment.Center) {
                        when {
                            state.isLoadingMore -> CircularProgressIndicator(color = Color.White, modifier = Modifier.size(24.dp))
                            state.isEmpty -> Text(
                                if (state.tab == UserTab.Stories) "No stories" else "No comments",
                                style = HN.titleStyle().copy(fontSize = 24.sp, color = Color.White.copy(alpha = 0.3f)),
                                modifier = Modifier.padding(vertical = 40.dp),
                            )
                        }
                    }
                }
            }
        }
        // The dark header reaches up behind the status bar.
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(HN.backgroundDark))
    }
}

/** A comment on a user page: which story it's on, the text, and how long ago. Opens its thread. */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun UserCommentRow(comment: UserComment, body: CommentBody?, openItem: (Long) -> Unit, onLink: (String) -> Unit) {
    val context = LocalContext.current
    var menuOpen by remember { mutableStateOf(false) }
    val url = "https://news.ycombinator.com/item?id=${comment.id}"
    Column(
        Modifier
            .fillMaxWidth()
            // The comments screen loads the comment to find its story; fetch both on touch down.
            .pointerInput(comment.id) {
                awaitEachGesture {
                    awaitFirstDown(requireUnconsumed = false)
                    AppContainer.prefetchComments(comment.id)
                    comment.storyId?.let(AppContainer::prefetchComments)
                }
            }
            .combinedClickable(
                onClickLabel = "Open thread",
                onClick = { openItem(comment.id) },
                onLongClickLabel = "More actions",
                onLongClick = { menuOpen = true },
            ),
    ) {
        HorizontalDivider(thickness = 0.5.dp, color = Color.White.copy(alpha = 0.2f))
        Column(Modifier.padding(horizontal = HN.padding, vertical = 15.dp), verticalArrangement = Arrangement.spacedBy(HN.padding)) {
            Row(verticalAlignment = Alignment.Top) {
                Text(
                    comment.storyTitle?.let { "on $it" } ?: "Comment",
                    style = HN.body.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.55f)),
                    maxLines = 2,
                    modifier = Modifier.weight(1f),
                )
                Spacer(Modifier.width(HN.padding))
                Text(RelativeTime.format(comment.time), style = HN.body.copy(fontSize = 13.sp, color = Color.White.copy(alpha = 0.4f)))
            }
            body?.let { CommentText(it, onLink) }
        }
        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(text = { Text("Open Thread") }, onClick = { menuOpen = false; openItem(comment.id) })
            DropdownMenuItem(text = { Text("Share") }, onClick = { menuOpen = false; context.share(url, null) })
            DropdownMenuItem(text = { Text("Copy Text") }, onClick = { menuOpen = false; context.copyToClipboard(body?.plainText ?: "") })
            DropdownMenuItem(text = { Text("Copy Link") }, onClick = { menuOpen = false; context.copyToClipboard(url) })
        }
    }
}
