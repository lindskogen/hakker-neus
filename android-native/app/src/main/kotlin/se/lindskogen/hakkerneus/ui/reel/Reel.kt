package se.lindskogen.hakkerneus.ui.reel

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.waitForUpOrCancellation
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.layout.layout
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import kotlin.math.abs
import kotlin.math.roundToInt
import se.lindskogen.hakkerneus.ui.Place
import se.lindskogen.hakkerneus.ui.Site
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette

/** One site's side of the reel: what it's called, its colours, and its places from the button up. */
class ReelSite(
    val site: Site,
    val label: String,
    /** Behind the reel, dimming the feed to near-black in the site's colour. */
    val tint: Color,
    /** The edge strip hinting at this site from the other one. */
    val accent: Color,
    val places: List<Place>,
    /** Where the site is now, marked "HERE"; null on the other site. */
    val here: Place?,
    /** The thin bar beside the place at this position. */
    val bar: (Int) -> Color,
)

/** Hacker News's places: Top, New, Saved and Search. */
fun hnReel(here: Place?) = ReelSite(
    Site.HackerNews, "Hacker News", Palette.hnReelTint, Palette.accent(),
    listOf(Place.Top, Place.New, Place.Saved, Place.Search),
    here,
    bar = { Palette.storyBackground(it * 4) },
)

/** lobste.rs's places: Hottest, Newest and Saved. No search: lobste.rs has no search API (hn-cib). */
fun lobstersReel(here: Place?) = ReelSite(
    Site.Lobsters, "lobste.rs", Palette.lobstersReelTint, Palette.lobstersAccent,
    listOf(Place.Hottest, Place.Newest, Place.Saved),
    here,
    bar = { Palette.lobstersBackground(it * 4) },
)

/**
 * The slot machine on the corner button: while the finger is down, where it is and which of the
 * two sites' places it points at. Positions are in the overlay's coordinates (the whole screen).
 */
class ReelState {
    var isOpen by mutableStateOf(false)
        private set
    var finger by mutableStateOf(Offset.Zero)
        private set
    /** Dragged sideways toward the middle: the reel shows [other]'s places. */
    var showsOther by mutableStateOf(false)
        private set
    var home by mutableStateOf<ReelSite?>(null)
        private set
    var other by mutableStateOf<ReelSite?>(null)
        private set

    /** The corner button, where the reel grows from. Kept up to date by the button. */
    var button by mutableStateOf(Rect.Zero)
    /** The overlay's top-left in the root, so the button's root bounds can be turned into the overlay's. */
    var origin by mutableStateOf(Offset.Zero)
    var onLeft by mutableStateOf(false)

    val shown: ReelSite? get() = if (showsOther) other else home

    /** The place level with the finger, or null within half a step of the button (letting go there cancels). */
    fun selection(step: Float): Int? {
        val count = shown?.places?.size ?: return null
        val raw = (button.center.y - finger.y) / step
        if (raw < 0.5f) return null
        return (raw.roundToInt() - 1).coerceIn(0, count - 1)
    }

    /** How far the finger is toward the middle of the screen, from the button. */
    val towardMiddle: Float get() = if (onLeft) finger.x - button.center.x else button.center.x - finger.x

    fun open(home: ReelSite, other: ReelSite, finger: Offset) {
        this.home = home
        this.other = other
        this.finger = finger
        showsOther = false
        isOpen = true
    }

    /** Moves the finger; returns true if that swapped the sites. */
    fun move(to: Offset, swapAt: Float, swapBackAt: Float): Boolean {
        finger = to
        val wanted = if (showsOther) towardMiddle > swapBackAt else towardMiddle > swapAt
        if (wanted == showsOther) return false
        showsOther = wanted
        return true
    }

    fun close() {
        isOpen = false
    }
}

object ReelMetrics {
    /** Between places. */
    val step = 58.dp
    /** Sideways toward the middle to swap to the other site, and back under this to swap back. */
    val swap = 60.dp
    val swapBack = 40.dp
    /** Held this long without moving, the reel opens without dragging. */
    const val HOLD_MILLIS = 300L
}

/**
 * The corner button's gesture on the feed. A tap is [onTap]. Pressing and dragging up opens the reel
 * straight away, as does holding still for [ReelMetrics.HOLD_MILLIS]; then the finger picks a place,
 * sideways swaps site, and letting go goes to [onChoose] (or nowhere, near the button).
 * [sites] gives the current site's reel and the other one's when the reel opens.
 */
suspend fun PointerInputScope.reelGesture(
    state: ReelState,
    haptics: HapticFeedback,
    sites: () -> Pair<ReelSite, ReelSite>,
    pressed: (Boolean) -> Unit,
    onTap: () -> Unit,
    onChoose: (ReelSite, Place, Offset) -> Unit,
    /** False where the button only taps (on the profile, where it goes back). */
    enabled: () -> Boolean,
) = awaitEachGesture {
    val down = awaitFirstDown()
    down.consume()
    pressed(true)
    if (!enabled()) {
        val up = waitForUpOrCancellation()
        pressed(false)
        if (up != null) { up.consume(); onTap() }
        return@awaitEachGesture
    }
    val slop = viewConfiguration.touchSlop
    val topLeft = state.button.topLeft - state.origin
    fun inOverlay(local: Offset) = topLeft + local

    // Before the reel: a tap, a drag up, a hold, or something else (which does nothing).
    var outcome = 0 // 1 tap, 2 open, 3 cancel
    val finished = withTimeoutOrNull(ReelMetrics.HOLD_MILLIS) {
        while (outcome == 0) {
            val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
            when {
                change == null -> outcome = 3
                !change.pressed -> { change.consume(); outcome = 1 }
                else -> {
                    val moved = change.position - down.position
                    if (-moved.y > slop && -moved.y > abs(moved.x)) outcome = 2
                    else if (moved.getDistance() > slop * 2) outcome = 3
                    change.consume()
                }
            }
        }
    }
    if (finished == null) {
        outcome = 2
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }
    if (outcome != 2) {
        pressed(false)
        if (outcome == 1) onTap()
        return@awaitEachGesture
    }

    val (home, other) = sites()
    val step = ReelMetrics.step.toPx()
    state.open(home, other, inOverlay(down.position))
    var selected = state.selection(step)
    while (true) {
        val change = awaitPointerEvent().changes.firstOrNull { it.id == down.id }
        if (change == null) break
        change.consume()
        if (!change.pressed) {
            val site = state.shown
            val index = state.selection(step)
            if (site != null && index != null) onChoose(site, site.places[index], state.finger)
            break
        }
        if (state.move(inOverlay(change.position), ReelMetrics.swap.toPx(), ReelMetrics.swapBack.toPx())) {
            haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
        }
        val now = state.selection(step)
        if (now != selected) {
            selected = now
            if (now != null) haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        }
    }
    pressed(false)
    state.close()
}

/** The reel itself, over the whole screen while [ReelState.isOpen]. */
@Composable
fun ReelOverlay(state: ReelState, modifier: Modifier = Modifier) {
    AnimatedVisibility(state.isOpen, modifier = modifier, enter = fadeIn(tween(120)), exit = fadeOut(tween(160))) {
        val shown = state.shown ?: return@AnimatedVisibility
        val hint = (if (state.showsOther) state.home else state.other) ?: return@AnimatedVisibility
        val tint by animateColorAsState(shown.tint, tween(200), label = "reel tint")
        Box(
            Modifier
                .fillMaxSize()
                .background(Brush.verticalGradient(listOf(tint.copy(alpha = 0.91f), tint.copy(alpha = 0.97f))))
        ) {
            EdgeStrip(hint, onRight = state.onLeft, modifier = Modifier.align(if (state.onLeft) Alignment.CenterEnd else Alignment.CenterStart))
            ReelPlaces(state, shown)
        }
    }
}

/** The other site's colour at the edge away from the button: drag that way to switch. */
@Composable
private fun EdgeStrip(site: ReelSite, onRight: Boolean, modifier: Modifier) {
    val shape = if (onRight) RoundedCornerShape(topStart = 8.dp, bottomStart = 8.dp) else RoundedCornerShape(topEnd = 8.dp, bottomEnd = 8.dp)
    Box(
        modifier.width(16.dp).fillMaxHeight(0.4f).clip(shape).background(site.accent),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            if (site.site == Site.HackerNews) "HN" else site.label.uppercase(),
            style = HN.body.copy(fontSize = 9.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.12.em, color = Color.White),
            softWrap = false,
            modifier = Modifier.rotate(if (onRight) -90f else 90f).layout { measurable, _ ->
                // Measured unconstrained, then laid out as if it were as narrow as the strip.
                val placeable = measurable.measure(androidx.compose.ui.unit.Constraints())
                layout(placeable.height, placeable.width) { placeable.place((placeable.height - placeable.width) / 2, (placeable.width - placeable.height) / 2) }
            },
        )
    }
}

@Composable
private fun ReelPlaces(state: ReelState, site: ReelSite) {
    val alignEnd = !state.onLeft
    Box(Modifier.fillMaxSize()) {
        val label = site.label.uppercase()
        Text(
            label,
            style = HN.body.copy(fontSize = 12.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.12.em, color = Color.White.copy(alpha = 0.6f)),
            modifier = Modifier.placeAt(alignEnd) { density ->
                Offset(edgeX(state, density), state.button.center.y - state.origin.y - with(density) { ReelMetrics.step.toPx() } * (site.places.size + 0.7f))
            },
        )
        site.places.forEachIndexed { index, place ->
            ReelItem(state, site, index, place, alignEnd)
        }
    }
}

/** Where the places line up: beside the thumb's path, toward the middle of the screen. */
private fun edgeX(state: ReelState, density: Density): Float = with(density) {
    val button = state.button.translate(-state.origin)
    val gap = 16.dp.toPx()
    val clear = 44.dp.toPx()
    if (state.onLeft) maxOf(button.right + gap, state.finger.x + clear)
    else minOf(button.left - gap, state.finger.x - clear)
}

@Composable
private fun ReelItem(state: ReelState, site: ReelSite, index: Int, place: Place, alignEnd: Boolean) {
    val density = androidx.compose.ui.platform.LocalDensity.current
    val step = with(density) { ReelMetrics.step.toPx() }
    val isSelected = state.selection(step) == index
    val selected by animateFloatAsState(if (isSelected) 1f else 0f, tween(110), label = "selected")
    // How many steps from the finger, for the ones not chosen: smaller and fainter further away.
    val distance = abs(index - ((state.button.center.y - state.finger.y) / step - 1f))
    val restingScale = (24f - 3f * (distance - 1f).coerceAtLeast(0f)).coerceAtLeast(16f) / 34f
    val restingAlpha = (0.6f - 0.1f * distance).coerceAtLeast(0.22f)
    val scale = restingScale + (1f - restingScale) * selected
    val alpha = restingAlpha + (1f - restingAlpha) * selected
    val bar = @Composable { Box(Modifier.width(4.dp).height(28.dp).clip(RoundedCornerShape(2.dp)).background(site.bar(index))) }
    val here = @Composable {
        if (place == site.here) Text(
            "HERE",
            style = HN.body.copy(fontSize = 10.sp, fontWeight = FontWeight.Medium, letterSpacing = 0.08.em, color = Color.White.copy(alpha = 0.8f)),
        )
    }
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = Modifier
            .placeAt(alignEnd) { d ->
                Offset(edgeX(state, d), state.button.center.y - state.origin.y - with(d) { ReelMetrics.step.toPx() } * (index + 1))
            }
            .graphicsLayer {
                scaleX = scale
                scaleY = scale
                this.alpha = alpha
                transformOrigin = TransformOrigin(if (alignEnd) 1f else 0f, 0.5f)
            },
    ) {
        if (!alignEnd) { bar(); Spacer(Modifier.size(12.dp)) } else { here(); Spacer(Modifier.size(10.dp)) }
        Text(
            place.title,
            style = HN.body.copy(fontSize = 34.sp, fontWeight = FontWeight.Light, color = Color.White),
            softWrap = false,
        )
        if (!alignEnd) { Spacer(Modifier.size(10.dp)); here() } else { Spacer(Modifier.size(12.dp)); bar() }
    }
}

/**
 * Places the content at an anchor read during layout (so following the finger only re-lays out):
 * its start there, or with [alignEnd] its end, centred vertically on it.
 */
private fun Modifier.placeAt(alignEnd: Boolean, anchor: (Density) -> Offset) = layout { measurable, constraints ->
    val placeable = measurable.measure(constraints.copy(minWidth = 0, minHeight = 0))
    layout(constraints.maxWidth, constraints.maxHeight) {
        val at = anchor(this@layout)
        val x = if (alignEnd) at.x - placeable.width else at.x
        placeable.place(x.roundToInt(), (at.y - placeable.height / 2f).roundToInt())
    }
}
