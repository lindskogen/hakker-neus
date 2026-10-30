package se.lindskogen.hakkerneus.ui.comments

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.windowInsetsTopHeight
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.data.FlatComment
import se.lindskogen.hakkerneus.data.HackerNewsLink
import se.lindskogen.hakkerneus.data.RelativeTime
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.html.CommentBody
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.copyToClipboard
import se.lindskogen.hakkerneus.ui.openInBrowser
import se.lindskogen.hakkerneus.ui.share
import se.lindskogen.hakkerneus.ui.sharedStory
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette

/** Indentation stops growing past this depth so deep threads stay readable. */
private const val MAX_INDENT_DEPTH = 8

/** A story with its comment tree (`CommentsList.tsx`). Tapping a comment collapses its replies. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun CommentsScreen(id: Long, openItem: (Long) -> Unit) {
    val model: CommentsViewModel = viewModel(key = "comments-$id") { CommentsViewModel(id) }
    val state by model.state.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()

    val openLink: (String) -> Unit = { url ->
        when (val link = HackerNewsLink.parse(url)) {
            is HackerNewsLink.Item -> openItem(link.id)
            else -> context.openInBrowser(url)
        }
    }

    val visible = state.thread.visible
    // List positions: 0 is the header, comments follow.
    LaunchedEffect(state.focusCommentId, visible.size) {
        val focus = state.focusCommentId ?: return@LaunchedEffect
        val index = visible.indexOfFirst { it.id == focus }
        if (index >= 0) {
            listState.scrollToItem(index + 1)
            model.focusHandled()
        }
    }

    Box(Modifier.fillMaxSize().background(HN.backgroundDark)) {
        PullToRefreshBox(isRefreshing = state.isRefreshing, onRefresh = model::refresh) {
            LazyColumn(state = listState, contentPadding = PaddingValues(bottom = 96.dp), modifier = Modifier.fillMaxSize()) {
                item(key = "header") { StoryHeader(id, state.story, state.storyBody, openLink) }
                when {
                    state.isLoading && visible.isEmpty() -> item { Status { CircularProgressIndicator(color = Color.White) } }
                    state.error != null -> item { Status { Message(HnIcons.error, state.error!!, HN.backgroundRed.copy(alpha = 0.5f)) } }
                    visible.isEmpty() -> item { Status { Message(HnIcons.bubble, "No comments here") } }
                    else -> items(visible, key = { it.id }) { flat ->
                        CommentRow(
                            flat = flat,
                            body = state.bodies[flat.id],
                            isOp = flat.comment.author != null && flat.comment.author == state.story?.author,
                            isCollapsed = state.thread.isCollapsed(flat.id),
                            hiddenReplies = state.thread.replyCounts[flat.id] ?: 0,
                            onToggle = { model.toggleCollapsed(flat.id) },
                            onLink = openLink,
                            onShare = { context.share(flat.comment.hackerNewsUrl) },
                            onCopyText = { context.copyToClipboard(state.bodies[flat.id]?.plainText ?: "", "Comment") },
                            onCopyLink = { context.copyToClipboard(flat.comment.hackerNewsUrl) },
                        )
                    }
                }
            }
        }

        // Next top-level thread, Apollo-style.
        if (visible.count { it.depth == 0 } > 1) {
            SmallFloatingActionButton(
                onClick = {
                    val current = listState.firstVisibleItemIndex
                    val next = visible.withIndex().firstOrNull { (index, comment) -> comment.depth == 0 && index + 1 > current }
                    next?.let { scope.launch { listState.animateScrollToItem(it.index + 1) } }
                },
                shape = CircleShape,
                containerColor = Color(0xE6404040),
                contentColor = Color.White,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .navigationBarsPadding()
                    .padding(end = 20.dp, bottom = HN.padding)
                    .size(52.dp)
                    .semantics { contentDescription = "Next thread" },
            ) { Icon(HnIcons.chevronDown, contentDescription = null, modifier = Modifier.size(22.dp)) }
        }
    }
}

/** Orange header with the title, reaching up behind the status bar. */
@Composable
private fun StoryHeader(id: Long, story: Story?, body: CommentBody?, onLink: (String) -> Unit) {
    Column(
        Modifier
            .fillMaxWidth()
            .sharedStory("card-$id")
            .background(HN.backgroundOrange)
            .statusBarsPadding()
            .heightIn(min = 100.dp)
            .combinedClickable(enabled = story?.url != null, onClick = { story?.url?.let(onLink) })
            .padding(start = HN.padding, end = HN.padding * 3, top = 20.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(5.dp),
    ) {
        Text(story?.title ?: "", style = HN.titleStyle(), modifier = Modifier.sharedStory("title-$id", bounds = false).semantics { heading() })
        if (story != null) {
            val byline = listOfNotNull("${story.score} points", story.author?.let { "by $it" }, story.displayDomain)
            Text(byline.joinToString(" · "), style = HN.body)
        }
        if (body != null && body.blocks.isNotEmpty()) {
            Spacer(Modifier.height(5.dp))
            CommentText(body, onLink)
        }
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun CommentRow(
    flat: FlatComment,
    body: CommentBody?,
    isOp: Boolean,
    isCollapsed: Boolean,
    hiddenReplies: Int,
    onToggle: () -> Unit,
    onLink: (String) -> Unit,
    onShare: () -> Unit,
    onCopyText: () -> Unit,
    onCopyLink: () -> Unit,
) {
    var menuOpen by remember { mutableStateOf(false) }
    val indent = (HN.padding * minOf(flat.depth, MAX_INDENT_DEPTH))
    val author = flat.comment.author ?: "deleted"

    Column(
        Modifier
            .fillMaxWidth()
            .combinedClickable(onClick = onToggle, onLongClick = { menuOpen = true })
            .padding(start = indent),
    ) {
        HorizontalDivider(thickness = 0.5.dp, color = Color.White.copy(alpha = 0.2f))
        Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min).padding(vertical = HN.padding)) {
            Box(Modifier.width(3.dp).fillMaxHeight().background(Palette.commentDepth(flat.depth)))
            Column(
                Modifier.weight(1f).padding(horizontal = HN.padding, vertical = 5.dp),
                verticalArrangement = Arrangement.spacedBy(HN.padding),
            ) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(5.dp)) {
                    Text(author, style = HN.body.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium), maxLines = 1)
                    if (isOp) {
                        Text(
                            "OP",
                            style = HN.body.copy(fontSize = 8.sp, lineHeight = 10.sp, fontWeight = FontWeight.Bold),
                            modifier = Modifier.clip(RoundedCornerShape(3.dp)).background(Color.White.copy(alpha = 0.13f)).padding(2.dp),
                        )
                    }
                    if (isCollapsed && hiddenReplies > 0) {
                        Text("+$hiddenReplies", style = HN.body.copy(fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Color.White.copy(alpha = 0.5f)))
                    }
                    Spacer(Modifier.weight(1f))
                    Text(RelativeTime.format(flat.comment.time), style = HN.body.copy(fontSize = 13.sp))
                }
                if (!isCollapsed && body != null) CommentText(body, onLink)
            }
        }

        DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
            DropdownMenuItem(text = { Text(if (isCollapsed) "Expand Thread" else "Collapse Thread") }, onClick = { menuOpen = false; onToggle() })
            DropdownMenuItem(text = { Text("Share") }, onClick = { menuOpen = false; onShare() })
            DropdownMenuItem(text = { Text("Copy Text") }, onClick = { menuOpen = false; onCopyText() })
            DropdownMenuItem(text = { Text("Copy Link") }, onClick = { menuOpen = false; onCopyLink() })
        }
    }
}

@Composable
private fun Status(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxWidth().heightIn(min = 400.dp), contentAlignment = Alignment.Center) { content() }
}

@Composable
private fun Message(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, tint: Color = Color.White.copy(alpha = 0.3f)) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(HN.padding)) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(60.dp))
        Text(text, style = HN.titleStyle().copy(fontSize = 24.sp, color = Color.White.copy(alpha = 0.3f)))
    }
}
