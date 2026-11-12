package se.lindskogen.hakkerneus.ui

import androidx.activity.compose.BackHandler
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalDrawerSheet
import androidx.compose.material3.NavigationDrawerItem
import androidx.compose.material3.NavigationDrawerItemDefaults
import androidx.compose.material3.Text
import androidx.compose.foundation.layout.Column
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerInputScope
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette
import kotlin.math.abs
import kotlin.math.roundToInt

/** Lets the corner button scroll a top-level screen to the top. One per place; the screen showing it binds its list. */
@Stable
class ScrollToTop {
    internal var list by mutableStateOf<LazyListState?>(null)

    /** Heights of the bound list's rows as last laid out, by index, for the rows scrolled past. */
    private val sizes = HashMap<Int, Int>()
    private var sizesOf: LazyListState? = null

    /** Whether the bound list is scrolled down more than half its height; observable. */
    val isScrolledDown by derivedStateOf { list?.let(::isPastHalf) ?: false }

    suspend fun scroll() {
        list?.animateScrollToItem(0)
    }

    /**
     * How far [list] is scrolled, from the heights of the rows above the first one showing (as
     * they were laid out, or the average of the ones showing for rows never seen) and how far
     * that one is scrolled, compared with half its height.
     */
    private fun isPastHalf(list: LazyListState): Boolean {
        if (sizesOf !== list) {
            sizes.clear()
            sizesOf = list
        }
        val info = list.layoutInfo
        val half = (info.viewportEndOffset - info.viewportStartOffset) / 2
        val visible = info.visibleItemsInfo
        if (half <= 0 || visible.isEmpty()) return false
        for (item in visible) sizes[item.index] = item.size + info.mainAxisItemSpacing
        val average = visible.sumOf { it.size } / visible.size
        var scrolled = list.firstVisibleItemScrollOffset
        for (index in 0 until list.firstVisibleItemIndex) {
            scrolled += sizes[index] ?: average
            if (scrolled > half) return true
        }
        return scrolled > half
    }
}

/** Whether TalkBack (or another touch-exploring service) is on; follows it changing. */
@Composable
fun rememberTouchExploration(): Boolean {
    val context = androidx.compose.ui.platform.LocalContext.current
    val manager = remember(context) { context.getSystemService(android.view.accessibility.AccessibilityManager::class.java) }
    var enabled by remember { mutableStateOf(manager?.isTouchExplorationEnabled == true) }
    DisposableEffect(manager) {
        val listener = android.view.accessibility.AccessibilityManager.TouchExplorationStateChangeListener { enabled = it }
        manager?.addTouchExplorationStateChangeListener(listener)
        onDispose { manager?.removeTouchExplorationStateChangeListener(listener) }
    }
    return enabled
}

/** Makes [hook] scroll [list] while this is composed. */
@Composable
fun BindScrollToTop(hook: ScrollToTop?, list: LazyListState) {
    if (hook == null) return
    DisposableEffect(hook, list) {
        hook.list = list
        onDispose { if (hook.list === list) hook.list = null }
    }
}

/** How far the sidebar is out: 0 closed, 1 open. */
@Stable
class SidebarState {
    internal val progress = Animatable(0f)
    val isOpen: Boolean get() = progress.value > 0f

    suspend fun open() = progress.animateTo(1f, spring(stiffness = 600f))
    suspend fun close() = progress.animateTo(0f, spring(stiffness = 600f))

    /** After a drag: open or closed, by where it was let go and how fast it was moving (in widths a second). */
    internal suspend fun settle(velocity: Float) {
        val open = velocity > 1f || (velocity > -1f && progress.value > 0.5f)
        if (open) open() else close()
    }
}

/** The accent line along the sidebar's outer edge. */
private val BorderWidth = 1.5.dp

/** How far in from the left edge a swipe opens the sidebar. */
private val EdgeWidth = 32.dp

/**
 * A sidebar behind [content], on the left: opening it slides the content (and its buttons) to
 * the right to show it. With [enabled], swiping in from the left edge pulls the content across
 * (only the edge, so rows keep their own swipes); a tap on the strip of content still showing,
 * swiping back, or back closes it. Android's gesture navigation also swipes from that edge, so a
 * band of it is kept for the sidebar.
 */
@Composable
fun SidebarLayout(
    state: SidebarState,
    enabled: Boolean,
    /** The colour of the line along the sidebar's outer edge: the site's. */
    accent: Color,
    sidebar: @Composable ColumnScope.() -> Unit,
    content: @Composable () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    BoxWithConstraints(
        Modifier.fillMaxSize().background(Color(0xFF26292E)),
    ) {
        val width = minOf(304.dp, maxWidth - 56.dp)
        val widthPx = with(density) { width.toPx() }
        val edgePx = with(density) { EdgeWidth.toPx() }
        val shadowPx = with(density) { 16.dp.toPx() }
        val progress = state.progress.value
        Box(
            Modifier
                .fillMaxSize()
                .then(
                    if (enabled) Modifier.pointerInput(widthPx, edgePx) {
                        edgeSwipe(
                            inEdge = { x -> x <= edgePx && !state.isOpen },
                            direction = 1f,
                            onDrag = { dx -> scope.launch { state.progress.snapTo((dx / widthPx).coerceIn(0f, 1f)) } },
                            onEnd = { velocity -> scope.launch { state.settle(velocity / widthPx) } },
                        )
                    } else Modifier,
                )
                .pointerInput(widthPx) {
                    openSidebarGestures(
                        edge = { state.progress.value * widthPx },
                        isOpen = { state.isOpen },
                        onDrag = { dx -> scope.launch { state.progress.snapTo((state.progress.value + dx / widthPx).coerceIn(0f, 1f)) } },
                        onEnd = { velocity -> scope.launch { state.settle(velocity / widthPx) } },
                        onTap = { scope.launch { state.close() } },
                    )
                },
        ) {
            if (progress > 0f) {
                // Behind the content, drifting in a little as it opens, and dimmed until it's out.
                Box(
                    Modifier
                        .width(width)
                        .fillMaxHeight()
                        .offset { IntOffset(((progress - 1f) * widthPx * 0.3f).roundToInt(), 0) }
                        .drawWithContent {
                            drawContent()
                            val line = BorderWidth.toPx()
                            drawRect(accent, topLeft = Offset(size.width - line, 0f), size = Size(line, size.height))
                            drawRect(Color.Black.copy(alpha = 0.5f * (1f - progress)))
                        },
                ) {
                    ModalDrawerSheet(
                        drawerShape = RectangleShape,
                        drawerContainerColor = Color(0xFF26292E),
                        drawerContentColor = Color.White,
                        modifier = Modifier.fillMaxSize(),
                    ) {
                        Column(Modifier.verticalScroll(rememberScrollState()).padding(vertical = 12.dp), content = sidebar)
                    }
                }
            }
            Box(
                Modifier
                    .fillMaxSize()
                    .offset { IntOffset((progress * widthPx).roundToInt(), 0) }
                    .drawBehind {
                        if (progress > 0f) {
                            drawRect(
                                Brush.horizontalGradient(
                                    listOf(Color.Transparent, Color.Black.copy(alpha = 0.45f)),
                                    startX = -shadowPx,
                                    endX = 0f,
                                ),
                                topLeft = Offset(-shadowPx, 0f),
                                size = Size(shadowPx, size.height),
                            )
                        }
                    }
                    .then(
                        // While it's out, the content is only something to tap to close it.
                        if (progress > 0f) Modifier.clearAndSetSemantics {
                            contentDescription = "Close sidebar"
                            onClick { scope.launch { state.close() }; true }
                        } else Modifier,
                    ),
            ) {
                content()
            }
        }
        if (enabled) {
            // Gesture navigation honours at most 200dp per edge.
            Box(Modifier.align(Alignment.CenterStart).width(EdgeWidth).height(200.dp).systemGestureExclusion())
        }
        BackHandler(enabled = progress > 0f) { scope.launch { state.close() } }
    }
}

/**
 * While the sidebar is out: a touch on the content beside it ([edge] is where that starts) is
 * kept from the content, closing the sidebar when tapped and dragging it when moved sideways; on
 * the sidebar itself only a drag back to the left is taken, so its places can be tapped and it
 * can scroll.
 */
private suspend fun PointerInputScope.openSidebarGestures(
    edge: () -> Float,
    isOpen: () -> Boolean,
    onDrag: (Float) -> Unit,
    onEnd: (Float) -> Unit,
    onTap: () -> Unit,
) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        if (!isOpen()) return@awaitEachGesture
        val onContent = down.position.x >= edge()
        if (onContent) down.consume()
        var moved = Offset.Zero
        var dragging = false
        val velocity = VelocityTracker()
        velocity.addPosition(down.uptimeMillis, down.position)
        while (true) {
            val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: break
            velocity.addPosition(change.uptimeMillis, change.position)
            val delta = change.positionChange()
            if (!dragging) {
                moved += delta
                if (moved.getDistance() > viewConfiguration.touchSlop) {
                    val sideways = abs(moved.x) > abs(moved.y)
                    if (sideways && (onContent || moved.x < 0f)) {
                        dragging = true
                    } else if (!onContent) {
                        return@awaitEachGesture
                    }
                }
            } else {
                onDrag(delta.x)
            }
            if (onContent || dragging) change.consume()
            if (!change.pressed) {
                when {
                    dragging -> onEnd(velocity.calculateVelocity().x)
                    onContent && moved.getDistance() <= viewConfiguration.touchSlop -> onTap()
                }
                return@awaitEachGesture
            }
        }
        if (dragging) onEnd(0f)
    }
}

/**
 * A drag that starts at an edge ([inEdge] of its x) and goes away from it ([direction] 1 for
 * right, -1 for left): taken from the content before it sees it, and reported as how far it's
 * gone ([onDrag]) and how fast it was let go ([onEnd]), both along [direction]. Anything else is
 * left alone.
 */
internal suspend fun PointerInputScope.edgeSwipe(
    inEdge: (x: Float) -> Boolean,
    direction: Float,
    onDrag: (Float) -> Unit,
    onEnd: (Float) -> Unit,
) {
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false, pass = PointerEventPass.Initial)
        if (!inEdge(down.position.x)) return@awaitEachGesture
        var moved = Offset.Zero
        while (true) {
            val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: return@awaitEachGesture
            if (!change.pressed) return@awaitEachGesture
            moved += change.positionChange()
            if (moved.getDistance() > viewConfiguration.touchSlop) {
                if (moved.x * direction <= abs(moved.y)) return@awaitEachGesture
                change.consume()
                break
            }
        }
        val velocity = VelocityTracker()
        val start = down.position.x
        while (true) {
            val change = awaitPointerEvent(PointerEventPass.Initial).changes.firstOrNull { it.id == down.id } ?: break
            velocity.addPosition(change.uptimeMillis, change.position)
            onDrag((change.position.x - start) * direction)
            change.consume()
            if (!change.pressed) break
        }
        onEnd(velocity.calculateVelocity().x * direction)
    }
}

/**
 * The sidebar's places: Hacker News's, lobste.rs's, then your profile (named for you when
 * signed in), Saved and Settings. [here] is highlighted.
 */
@Composable
fun ColumnScope.SidebarPlaces(here: Place, username: String?, go: (Place) -> Unit, openSettings: () -> Unit) {
    SidebarHeading(Site.HackerNews.title, HN.accent)
    for (place in listOf(Place.Top, Place.New, Place.Search)) SidebarItem(place.title, place == here, HN.accent) { go(place) }
    SidebarHeading(Site.Lobsters.title, Palette.lobstersAccent)
    for (place in listOf(Place.Hottest, Place.Newest)) SidebarItem(place.title, place == here, Palette.lobstersAccent) { go(place) }
    HorizontalDivider(Modifier.padding(horizontal = 28.dp, vertical = 12.dp), color = Color.White.copy(alpha = 0.12f))
    SidebarItem(username ?: Place.Profile.title, here == Place.Profile, Color.White, icon = HnIcons.person) { go(Place.Profile) }
    SidebarItem(Place.Saved.title, here == Place.Saved, Palette.savedStoryBackground(0), icon = HnIcons.heart) { go(Place.Saved) }
    SidebarItem("Settings", selected = false, Color.White, icon = HnIcons.gear, onClick = openSettings)
}

@Composable
private fun SidebarHeading(title: String, color: Color) {
    Text(
        title,
        color = color,
        fontSize = 14.sp,
        modifier = Modifier.padding(start = 28.dp, end = 28.dp, top = 16.dp, bottom = 8.dp).semantics { heading() },
    )
}

@Composable
private fun SidebarItem(
    title: String,
    selected: Boolean,
    color: Color,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    onClick: () -> Unit,
) {
    NavigationDrawerItem(
        label = { Text(title, fontSize = 17.sp) },
        selected = selected,
        onClick = onClick,
        icon = icon?.let { { Icon(it, contentDescription = null, modifier = Modifier.size(22.dp)) } },
        colors = NavigationDrawerItemDefaults.colors(
            selectedContainerColor = color.copy(alpha = 0.22f),
            unselectedContainerColor = Color.Transparent,
            selectedTextColor = Color.White,
            unselectedTextColor = Color.White.copy(alpha = 0.85f),
            selectedIconColor = Color.White,
            unselectedIconColor = Color.White.copy(alpha = 0.7f),
        ),
        modifier = Modifier.padding(NavigationDrawerItemDefaults.ItemPadding),
    )
}
