package se.lindskogen.hakkerneus.ui

import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier

/** Set by AppNavigation so rows and the comments header can share elements between screens. */
@OptIn(ExperimentalSharedTransitionApi::class)
val LocalSharedTransitionScope = compositionLocalOf<SharedTransitionScope?> { null }
val LocalNavAnimatedScope = compositionLocalOf<AnimatedVisibilityScope?> { null }

/**
 * A story's card or title, shared between its row and the comments header, so opening the
 * comments grows the row into the header (the iOS StoryTransition). No-op outside navigation.
 */
@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
fun Modifier.sharedStory(key: String, bounds: Boolean = true): Modifier {
    val shared = LocalSharedTransitionScope.current ?: return this
    val animated = LocalNavAnimatedScope.current ?: return this
    return with(shared) {
        val state = rememberSharedContentState(key)
        if (bounds) sharedBounds(state, animated) else sharedElement(state, animated)
    }
}
