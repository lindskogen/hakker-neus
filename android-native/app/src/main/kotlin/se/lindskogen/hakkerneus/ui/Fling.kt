package se.lindskogen.hakkerneus.ui

import android.view.ViewConfiguration
import androidx.compose.animation.core.DecayAnimationSpec
import androidx.compose.animation.core.calculateTargetValue
import androidx.compose.animation.splineBasedDecay
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import kotlin.math.abs

/**
 * Where a swipe let go comes to rest if it coasts on like a fling in a scrolling list, using the
 * system's fling physics and minimum fling speed. Swipes decide by this whether they were flung
 * far enough, rather than by a speed limit of their own.
 */
class Fling(private val decay: DecayAnimationSpec<Float>, private val minimumVelocity: Float) {
    /** Where something at [position] moving at [velocity] (both in pixels) comes to rest. */
    fun project(position: Float, velocity: Float): Float =
        if (abs(velocity) < minimumVelocity) position else decay.calculateTargetValue(position, velocity)
}

@Composable
fun rememberFling(): Fling {
    val density = LocalDensity.current
    val context = LocalContext.current
    return remember(density, context) {
        Fling(splineBasedDecay(density), ViewConfiguration.get(context).scaledMinimumFlingVelocity.toFloat())
    }
}
