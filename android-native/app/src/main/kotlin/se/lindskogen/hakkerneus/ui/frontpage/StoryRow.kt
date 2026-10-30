package se.lindskogen.hakkerneus.ui.frontpage

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
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.ui.HnIcons
import se.lindskogen.hakkerneus.ui.sharedStory
import se.lindskogen.hakkerneus.ui.theme.HN
import kotlin.math.roundToInt

/** Actions a row offers, from taps, swipes, the long-press menu and accessibility. */
class StoryRowActions(
    val open: (Story) -> Unit,
    val openComments: (Story) -> Unit,
    val toggleSaved: (Story) -> Unit,
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
fun StoryRow(story: Story, background: Color, isSaved: Boolean, actions: StoryRowActions, modifier: Modifier = Modifier) {
    val density = LocalDensity.current
    val view = LocalView.current
    val scope = rememberCoroutineScope()
    val offset = remember { Animatable(0f) } // dp, after resistance
    var translation by remember { mutableStateOf(0f) }
    var armed by remember { mutableStateOf<StorySwipe.Action?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    var savedAtSwipeStart by remember { mutableStateOf(isSaved) }
    val swipe = StorySwipe(offset.value)

    fun settle(after: Long = 0) = scope.launch {
        delay(after)
        offset.animateTo(0f, spring(dampingRatio = 0.85f, stiffness = Spring.StiffnessMediumLow))
    }

    Box(
        modifier
            .fillMaxWidth()
            .background(HN.backgroundDark)
            .semantics {
                customActions = listOf(
                    CustomAccessibilityAction("Open comments") { actions.openComments(story); true },
                    CustomAccessibilityAction(if (isSaved) "Unsave" else "Save") { actions.toggleSaved(story); true },
                )
            },
    ) {
        // Behind the row: the heart on the left, the comment count on the right.
        Box(Modifier.matchParentSize()) {
            Icon(
                if (savedAtSwipeStart) HnIcons.heartBroken else HnIcons.heart,
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
                .heightIn(min = 100.dp)
                .sharedStory("card-${story.id}")
                .background(background)
                .pointerInput(story.id) {
                    detectHorizontalDragGestures(
                        onDragStart = {
                            translation = 0f
                            armed = null
                            savedAtSwipeStart = isSaved
                        },
                        onHorizontalDrag = { change, dx ->
                            change.consume()
                            translation += dx / density.density
                            val next = StorySwipe.forTranslation(translation, canUpvote = false)
                            scope.launch { offset.snapTo(next.offset) }
                            val action = next.armedAction(canUpvote = false)
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
                                StorySwipe.Action.Upvote, null -> settle()
                            }
                            armed = null
                        },
                        onDragCancel = { settle(); armed = null },
                    )
                }
                .combinedClickable(onClick = { actions.open(story) }, onLongClick = { menuOpen = true }),
        ) {
            Column(Modifier.padding(start = HN.padding, end = HN.padding * 3, top = 20.dp, bottom = 20.dp)) {
                Text(story.title, style = HN.titleStyle(), modifier = Modifier.sharedStory("title-${story.id}", bounds = false))
                story.displayDomain?.let {
                    Text(it, style = HN.body.copy(fontSize = 14.sp, color = Color.White.copy(alpha = 0.7f)), maxLines = 1)
                }
            }
            if (isSaved) {
                Icon(
                    HnIcons.heart, contentDescription = "Saved", tint = Color.White.copy(alpha = 0.3f),
                    modifier = Modifier.align(Alignment.TopEnd).padding(HN.padding).size(26.dp),
                )
            }
            Text(
                "${story.score}",
                style = HN.body.copy(fontSize = 30.sp, lineHeight = 34.sp, color = Color.White.copy(alpha = 0.3f)),
                modifier = Modifier.align(Alignment.BottomEnd).padding(HN.padding),
            )

            DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                fun item(title: String, action: () -> Unit) = @Composable {
                    DropdownMenuItem(text = { Text(title) }, onClick = { menuOpen = false; action() })
                }
                item("Comments (${story.commentCount})") { actions.openComments(story) }()
                if (story.url != null) item("Open Link") { actions.open(story) }()
                item(if (isSaved) "Unsave" else "Save") { actions.toggleSaved(story) }()
                item("Share") { actions.share(story) }()
                item("Copy Link") { actions.copyLink(story) }()
                if (story.url != null) item("Copy Comments Link") { actions.copyCommentsLink(story) }()
            }
        }
    }
}
