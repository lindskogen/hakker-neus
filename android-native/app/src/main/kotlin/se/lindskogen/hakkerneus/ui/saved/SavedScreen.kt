package se.lindskogen.hakkerneus.ui.saved

import se.lindskogen.hakkerneus.data.isLobsters
import se.lindskogen.hakkerneus.ui.frontpage.LobstersStoryRow
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.HackerNewsLink
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.copyToClipboard
import se.lindskogen.hakkerneus.ui.frontpage.StoryRow
import se.lindskogen.hakkerneus.ui.frontpage.StoryRowActions
import se.lindskogen.hakkerneus.ui.openInBrowser
import se.lindskogen.hakkerneus.ui.share
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette

/**
 * The profile page: who's signed in and the saved stories, newest first, in red. Reached from
 * the front page's corner button; rows work like on the front page.
 */
@Composable
fun SavedScreen(
    username: String?,
    openComments: (Story) -> Unit,
    openItem: (Long) -> Unit,
    openSettings: () -> Unit,
    openSearch: () -> Unit,
    signIn: () -> Unit,
) {
    val upvoted by AppContainer.session.upvoted.collectAsState()
    val entries by AppContainer.saved.entries.collectAsState()
    val visits by AppContainer.visited.visits.collectAsState()
    val savedComments by AppContainer.savedComments.entries.collectAsState()
    var showsComments by androidx.compose.runtime.saveable.rememberSaveable { androidx.compose.runtime.mutableStateOf(false) }
    val commentBodies = androidx.compose.runtime.remember(savedComments) {
        savedComments.associate { it.id to se.lindskogen.hakkerneus.html.CommentBody.parse(it.text) }
    }
    val context = LocalContext.current
    val haptics = LocalHapticFeedback.current
    val openUser = se.lindskogen.hakkerneus.ui.LocalOpenUser.current
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

    Box(Modifier.fillMaxSize().background(HN.backgroundDark)) {
        LazyColumn(contentPadding = PaddingValues(bottom = 96.dp), modifier = Modifier.fillMaxSize()) {
            item(key = "profile") {
                Row(
                    Modifier.fillMaxWidth().statusBarsPadding().padding(start = 20.dp, end = 20.dp, top = 20.dp, bottom = 20.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(Modifier.weight(1f)) {
                        // Signed out, the name's place is an obvious way to sign in.
                        Text(
                            username ?: "Sign in",
                            style = HN.titleStyle().copy(color = if (username == null) HN.accent else Color.White),
                            modifier = Modifier
                                .semantics { heading() }
                                .clickable(onClickLabel = if (username == null) "Sign in" else "Your Hacker News page") {
                                    if (username == null) signIn() else openUser(username)
                                },
                        )
                        val stories = if (entries.size == 1) "1 saved story" else "${entries.size} saved stories"
                        val comments = if (savedComments.size == 1) "1 comment" else "${savedComments.size} comments"
                        Text(
                            if (savedComments.isEmpty()) stories else "$stories · $comments",
                            style = HN.body.copy(fontSize = 14.sp, color = Color.White.copy(alpha = 0.6f)),
                        )
                    }
                    IconButton(onClick = openSearch, modifier = Modifier.offset(x = 12.dp)) { Icon(HnIcons.search, contentDescription = "Search", tint = Color.White) }
                    // 48dp to tap, with the gear at its right edge so the margins match the name's.
                    IconButton(onClick = openSettings, modifier = Modifier.offset(x = 12.dp)) { Icon(HnIcons.gear, contentDescription = "Settings", tint = Color.White) }
                }
            }
            item(key = "tabs") {
                se.lindskogen.hakkerneus.ui.TextTabs(listOf("Stories", "Comments"), if (showsComments) 1 else 0, onSelect = { showsComments = it == 1 })
            }
            if (showsComments) itemsIndexed(savedComments, key = { _, comment -> "c${comment.id}" }) { _, comment ->
                se.lindskogen.hakkerneus.ui.user.UserCommentRow(
                    se.lindskogen.hakkerneus.data.UserComment(comment.id, comment.text, comment.time, comment.storyId, comment.storyTitle),
                    commentBodies[comment.id],
                    openItem = openItem,
                    onLink = { url ->
                        when (val link = HackerNewsLink.parse(url)) {
                            is HackerNewsLink.Item -> openItem(link.id)
                            is HackerNewsLink.User -> openUser(link.name)
                            else -> context.openInBrowser(url)
                        }
                    },
                    author = comment.author,
                    onUnsave = { AppContainer.savedComments.remove(comment.id) },
                )
            }
            if (!showsComments) itemsIndexed(entries, key = { _, entry -> entry.story.id }) { index, entry ->
                visits.size // re-read when visits change
                if (entry.story.isLobsters) LobstersStoryRow(
                    entry.story, Palette.savedStoryBackground(index), isSaved = true, actions = actions,
                    isVisited = AppContainer.visited.isVisited(entry.story.id),
                    showsSavedBadge = false,
                ) else StoryRow(
                    entry.story, Palette.savedStoryBackground(index), isSaved = true, actions = actions,
                    isVisited = AppContainer.visited.isVisited(entry.story.id),
                    showsSavedBadge = false,
                    isUpvoted = entry.story.id in upvoted,
                    score = AppContainer.session.displayedScore(entry.story.id, entry.story.score),
                )
                HorizontalDivider(thickness = 0.5.dp, color = Color.Black)
            }
            if (if (showsComments) savedComments.isEmpty() else entries.isEmpty()) {
                item {
                    Column(
                        Modifier.fillMaxWidth().heightIn(min = 400.dp),
                        verticalArrangement = Arrangement.Center,
                        horizontalAlignment = Alignment.CenterHorizontally,
                    ) {
                        Icon(HnIcons.heart, contentDescription = null, tint = Color.White.copy(alpha = 0.3f), modifier = Modifier.size(60.dp))
                        Text(if (showsComments) "No saved comments" else "No saved stories", style = HN.titleStyle().copy(fontSize = 24.sp, color = Color.White.copy(alpha = 0.3f)))
                    }
                }
            }
        }
        // The dark header reaches up behind the status bar.
        Box(Modifier.fillMaxWidth().windowInsetsTopHeight(WindowInsets.statusBars).background(HN.backgroundDark))
    }
}
