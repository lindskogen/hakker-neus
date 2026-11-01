package se.lindskogen.hakkerneus.ui.frontpage

import se.lindskogen.hakkerneus.AppContainer
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitEachGesture
import se.lindskogen.hakkerneus.ui.UserMenuItem
import se.lindskogen.hakkerneus.ui.LocalOpenUser
import androidx.compose.ui.platform.LocalContext
import android.os.Build
import android.view.HapticFeedbackConstants
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.scale
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.data.RelativeTime
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.sharedStory
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette
import kotlin.math.roundToInt

/** Actions a row offers, from taps, swipes, the long-press menu and accessibility. */
class StoryRowActions(
    val open: (Story) -> Unit,
    val openComments: (Story) -> Unit,
    val toggleSaved: (Story) -> Unit,
    val toggleUpvote: (Story) -> Unit,
    val share: (Story) -> Unit,
    val copyLink: (Story) -> Unit,
    val copyCommentsLink: (Story) -> Unit,
)

/**
 * A row on the front page (`ListItem.tsx`): title on an orange background, domain underneath,
 * the score faded in the corner, a heart when saved. Swipe right to save, left for comments.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun StoryRow(
    story: Story,
    background: Color,
    isSaved: Boolean,
    actions: StoryRowActions,
    modifier: Modifier = Modifier,
    isVisited: Boolean = false,
    newComments: Int? = null,
    showsSavedBadge: Boolean = true,
    isUpvoted: Boolean = false,
    score: Int = story.score,
    /** A quieter row for lists inside other screens (a user's stories): a smaller title and one
     * dim line with the domain, points, comments and age, and no big score. */
    compact: Boolean = false,
) {
    val context = LocalContext.current
    val openUser = LocalOpenUser.current
    val density = LocalDensity.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(0f) } // dp, after resistance
    var translation by remember { mutableStateOf(0f) }
    var armed by remember { mutableStateOf<StorySwipe.Action?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    var savedAtSwipeStart by remember { mutableStateOf(isSaved) }
    var upvotedAtSwipeStart by remember { mutableStateOf(isUpvoted) }
    val swipe = StorySwipe(offset.value)
    val upvoteStage = swipe.armedAction(canUpvote = AppContainer.session.isSignedIn) == StorySwipe.Action.Upvote

    fun settle(after: Long = 0) = scope.launch {
        delay(after)
        offset.animateTo(0f, spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow))
    }

    Box(
        modifier
            .fillMaxWidth()
            .background(HN.backgroundDark),
    ) {
        // Behind the row: the heart on the left (an up arrow on blue at the upvote stage),
        // the comment count on the right.
        Box(Modifier.matchParentSize().background(if (upvoteStage) Palette.upvoteStage else Color.Transparent)) {
            Icon(
                when {
                    upvoteStage -> if (upvotedAtSwipeStart) HnIcons.undo else HnIcons.arrowUp
                    savedAtSwipeStart -> HnIcons.heartBroken
                    else -> HnIcons.heart
                },
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier
                    .align(Alignment.CenterStart)
                    .padding(start = 20.dp)
                    .size(40.dp)
                    .offset { IntOffset(with(density) { swipe.heartTranslation.dp.roundToPx() }, 0) }
                    .alpha(swipe.heartAlpha),
            )
            Text(
                "${story.commentCount}",
                style = HN.body.copy(fontSize = 50.sp, lineHeight = 56.sp),
                maxLines = 1,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = HN.padding)
                    .scale(swipe.commentCountScale.coerceAtLeast(0.001f)),
            )
        }

        // The row itself, which moves with the finger.
        Box(
            Modifier
                .offset { IntOffset(with(density) { offset.value.dp.roundToPx() }, 0) }
                .fillMaxWidth()
                .heightIn(min = if (compact) 0.dp else 100.dp)
                .sharedStory("card-${story.id}")
                .background(background)
                .pointerInput(story.id) {
                    detectHorizontalDragGestures(
                        onDragStart = {
                            AppContainer.prefetchComments(story.id)
                            translation = 0f
                            armed = null
                            savedAtSwipeStart = isSaved
                            upvotedAtSwipeStart = isUpvoted
                        },
                        onHorizontalDrag = { change, dx ->
                            change.consume()
                            translation += dx / density.density
                            val next = StorySwipe.forTranslation(translation, canUpvote = AppContainer.session.isSignedIn)
                            scope.launch { offset.snapTo(next.offset) }
                            val action = next.armedAction(canUpvote = AppContainer.session.isSignedIn)
                            if (action != armed) {
                                armed = action
                                if (action != null) {
                                    val feedback = if (Build.VERSION.SDK_INT >= 34) HapticFeedbackConstants.GESTURE_THRESHOLD_ACTIVATE
                                    else HapticFeedbackConstants.VIRTUAL_KEY
                                    view.performHapticFeedback(feedback)
                                }
                            }
                        },
                        onDragEnd = {
                            when (armed) {
                                StorySwipe.Action.Comments -> { actions.openComments(story); settle() }
                                StorySwipe.Action.Save -> { actions.toggleSaved(story); settle(after = 100) }
                                StorySwipe.Action.Upvote -> { actions.toggleUpvote(story); settle(after = 100) }
                                null -> settle()
                            }
                            armed = null
                        },
                        onDragCancel = { settle(); armed = null },
                    )
                }
                // On touch down, before it's clear whether this is a tap, swipe or long press.
                .pointerInput(story.id) {
                    awaitEachGesture {
                        awaitFirstDown(requireUnconsumed = false)
                        AppContainer.prefetchComments(story.id)
                    }
                }
                .combinedClickable(
                    onClickLabel = if (story.url == null) "Open comments" else "Open link",
                    onClick = { actions.open(story) },
                    onLongClickLabel = "More actions",
                    onLongClick = { menuOpen = true; story.author?.let(AppContainer::prefetchUser) },
                )
                // TalkBack: the swipes as actions (the row is the focusable node, so they go here).
                .semantics {
                    if (isVisited) stateDescription = "Read"
                    customActions = listOf(
                        CustomAccessibilityAction("Open comments") { actions.openComments(story); true },
                        CustomAccessibilityAction(if (isSaved) "Unsave" else "Save") { actions.toggleSaved(story); true },
                        CustomAccessibilityAction(if (isUpvoted) "Unvote" else "Upvote") { actions.toggleUpvote(story); true },
                    )
                },
        ) {
            val vertical = if (compact) 15.dp else 20.dp
            Column(Modifier.padding(start = HN.padding, end = if (compact) HN.padding else HN.padding * 3, top = vertical, bottom = vertical)) {
                // Read stories fade back, so unread ones stand out.
                val title = HN.titleStyle()
                Text(
                    story.title,
                    style = if (compact) title.copy(fontSize = title.fontSize * 0.8f, lineHeight = title.lineHeight * 0.8f) else title,
                    modifier = Modifier.sharedStory("title-${story.id}", bounds = false).alpha(if (isVisited) 0.55f else 1f),
                )
                if (compact) {
                    val details = listOfNotNull(
                        story.displayDomain, (if (isUpvoted) "▲ " else "") + if (score == 1) "1 point" else "$score points",
                        if (story.commentCount == 1) "1 comment" else "${story.commentCount} comments", RelativeTime.format(story.time),
                    )
                    Text(details.joinToString(" · "), style = HN.body.copy(fontSize = 13.sp, color = Color.White.copy(alpha = 0.45f)), modifier = Modifier.padding(top = 4.dp))
                } else {
                    val details = listOfNotNull(story.displayDomain, newComments?.let { "$it new" })
                    if (details.isNotEmpty()) {
                        Text(details.joinToString(" · "), style = HN.body.copy(fontSize = 14.sp, color = Color.White.copy(alpha = 0.7f)), maxLines = 1)
                    }
                }
            }
            if (isSaved && showsSavedBadge) {
                Icon(
                    HnIcons.heart, contentDescription = "Saved", tint = Color.White.copy(alpha = 0.3f),
                    modifier = Modifier.align(Alignment.TopEnd).padding(HN.padding).size(26.dp),
                )
            }
            if (!compact) Text(
                if (isUpvoted) "▲ $score" else "$score",
                style = HN.body.copy(fontSize = 30.sp, lineHeight = 34.sp, color = Color.White.copy(alpha = if (isUpvoted) 0.85f else 0.3f)),
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(HN.padding)
                    .semantics {
                        contentDescription = listOfNotNull("$score points", if (isUpvoted) "upvoted" else null, "${story.commentCount} comments").joinToString(", ")
                    },
            )

            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                fun item(title: String, action: () -> Unit) = @Composable {
                    DropdownMenuItem(text = { Text(title) }, onClick = { menuOpen = false; action() })
                }
                item("Comments (${story.commentCount})") { actions.openComments(story) }()
                if (story.url != null) item("Open Link") { actions.open(story) }()
                item(if (isUpvoted) "Unvote" else "Upvote") { actions.toggleUpvote(story) }()
                item(if (isSaved) "Unsave" else "Save") { actions.toggleSaved(story) }()
                item("Share") { actions.share(story) }()
                item("Copy Link") { actions.copyLink(story) }()
                if (story.url != null) item("Copy Comments Link") { actions.copyCommentsLink(story) }()
                story.author?.let { author -> UserMenuItem(author) { menuOpen = false; openUser(author) } }
            }
        }
    }
}
