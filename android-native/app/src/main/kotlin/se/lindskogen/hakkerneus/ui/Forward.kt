package se.lindskogen.hakkerneus.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.systemGestureExclusion
import androidx.compose.material3.Icon
import androidx.compose.material3.Surface
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.lifecycle.ViewModel
import androidx.lifecycle.ViewModelStore
import androidx.lifecycle.ViewModelStoreOwner
import androidx.lifecycle.viewmodel.compose.LocalViewModelStoreOwner
import androidx.navigation.NavBackStackEntry
import androidx.navigation.NavController
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.toRoute
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlin.math.roundToInt

/** Links opened in the browser, so the browser can be gone forward to after coming back from it. */
internal val browserOpened = MutableSharedFlow<String>(extraBufferCapacity = 8)

/** Something forward goes to: a screen left with back, or the browser last opened. */
sealed interface ForwardItem {
    /** Comments or a user page, with its view models (and so its scroll position) kept. */
    class Screen(val route: Any, val store: ViewModelStore) : ForwardItem
    class Browser(val url: String) : ForwardItem
}

/**
 * Forward, as in a browser: screens left with back are kept, view models and all, so swiping in
 * from the right edge brings back the last one as it was left. Opening something new forgets
 * them. Comments and user pages keep their view models in stores held here rather than in their
 * back-stack entries, which Navigation clears when they're popped.
 *
 * Activity-scoped, so it outlives rotation along with the back stack.
 */
class ForwardHistory : ViewModel() {
    /** Last is next. */
    val items = mutableStateListOf<ForwardItem>()
    /** View model stores of comments and user pages in the back stack, by entry ID. */
    private val stores = mutableMapOf<String, ViewModelStore>()
    /** The forwardable entries last seen in the back stack, bottom to top. */
    private var shown: List<NavBackStackEntry> = emptyList()
    /** Entries pushed by going forward, which don't forget the rest. */
    private val forwarded = mutableSetOf<String>()

    val next: ForwardItem? get() = items.lastOrNull()

    fun storeFor(entry: NavBackStackEntry): ViewModelStore = stores.getOrPut(entry.id) { ViewModelStore() }

    /** Follows the back stack: what was popped can be gone forward to; something new pushed forgets it all. */
    fun backStackChanged(stack: List<NavBackStackEntry>) {
        val now = stack.filter { forwardRoute(it) != null }
        val ids = now.map { it.id }.toSet()
        val before = shown.map { it.id }.toSet()
        val popped = shown.filter { it.id !in ids }
        val pushed = now.filter { it.id !in before }
        shown = now

        // Top first, so the lowest popped is next.
        for (entry in popped.asReversed()) {
            val store = stores.remove(entry.id) ?: continue
            val route = forwardRoute(entry) ?: continue
            add(ForwardItem.Screen(route, store))
        }
        if (pushed.any { forwarded.remove(it.id).not() }) forget()
    }

    /** A link opened in the browser: the only thing forward goes to now. */
    fun browserOpened(url: String) {
        forget()
        add(ForwardItem.Browser(url))
    }

    /** Goes to [next]. The browser stays next, since coming back from it is going back. */
    fun goForward(nav: NavController, openInBrowser: (String) -> Unit) {
        when (val item = next ?: return) {
            is ForwardItem.Browser -> openInBrowser(item.url)
            is ForwardItem.Screen -> {
                items.removeAt(items.lastIndex)
                nav.navigate(item.route)
                val entry = nav.currentBackStackEntry ?: return item.store.clear()
                // Before the screen is composed, so it finds its view models.
                stores.put(entry.id, item.store)?.clear()
                forwarded += entry.id
            }
        }
    }

    private fun add(item: ForwardItem) {
        items += item
        while (items.size > MAX_ITEMS) (items.removeAt(0) as? ForwardItem.Screen)?.store?.clear()
    }

    private fun forget() {
        for (item in items) (item as? ForwardItem.Screen)?.store?.clear()
        items.clear()
    }

    override fun onCleared() {
        forget()
        stores.values.forEach { it.clear() }
        stores.clear()
    }

    private companion object {
        const val MAX_ITEMS = 8
    }
}

/** The route to navigate to again for an entry forward can bring back: comments or a user page. */
private fun forwardRoute(entry: NavBackStackEntry): Any? {
    val destination = entry.destination
    return when {
        destination.hasRoute<Comments>() -> entry.toRoute<Comments>()
        destination.hasRoute<User>() -> entry.toRoute<User>()
        else -> null
    }
}

/** [content] with its view models in [history]'s store for [entry], so they outlive the entry being popped. */
@Composable
fun KeptViewModels(history: ForwardHistory, entry: NavBackStackEntry, content: @Composable () -> Unit) {
    val owner = remember(entry.id) {
        val store = history.storeFor(entry)
        object : ViewModelStoreOwner {
            override val viewModelStore = store
        }
    }
    CompositionLocalProvider(LocalViewModelStoreOwner provides owner, content = content)
}

/** How far in from the right edge a swipe goes forward. */
private val EdgeWidth = 32.dp
/** How far a swipe has to go to go forward. */
private val Threshold = 96.dp

/**
 * With [enabled], swiping in from the right edge of [content] goes forward ([onForward]): an arrow
 * follows the finger out of the edge, and letting go far enough along (or flinging) goes. Only the
 * edge, so rows and code blocks keep their own swipes; a band of it is kept from Android's gesture
 * navigation.
 */
@Composable
fun ForwardSwipeLayout(enabled: Boolean, onForward: () -> Unit, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val edgePx = with(density) { EdgeWidth.toPx() }
    val thresholdPx = with(density) { Threshold.toPx() }
    var pulled by remember { mutableFloatStateOf(0f) }
    Box(
        Modifier.fillMaxSize().then(
            if (enabled) Modifier.pointerInput(edgePx, thresholdPx) {
                edgeSwipe(
                    inEdge = { x -> x >= size.width - edgePx },
                    direction = -1f,
                    onDrag = { distance -> pulled = distance.coerceAtLeast(0f) },
                    onEnd = { velocity ->
                        // Velocity is along the swipe (towards the left), in pixels a second.
                        if (pulled >= thresholdPx || (velocity > 1500f && pulled > edgePx)) onForward()
                        pulled = 0f
                    },
                )
            } else Modifier,
        ),
    ) {
        content()
        if (enabled) {
            // Gesture navigation honours at most 200dp per edge.
            Box(Modifier.align(Alignment.CenterEnd).width(EdgeWidth).height(200.dp).systemGestureExclusion())
        }
        if (pulled > 0f) {
            val progress = (pulled / thresholdPx).coerceIn(0f, 1f)
            Surface(
                shape = CircleShape,
                color = if (progress >= 1f) Color(0xF2606060) else Color(0xE6404040),
                contentColor = Color.White,
                shadowElevation = 6.dp,
                modifier = Modifier
                    .align(Alignment.CenterEnd)
                    .padding(end = 12.dp)
                    // Out from under the edge, as far as the finger, but no further than the threshold.
                    .offset { IntOffset(((1f - progress) * (thresholdPx * 0.6f)).roundToInt(), 0) }
                    .alpha(progress)
                    .size(44.dp),
            ) {
                Box(contentAlignment = Alignment.Center) {
                    Icon(HnIcons.forward, contentDescription = null, modifier = Modifier.size(24.dp))
                }
            }
        }
    }
}
