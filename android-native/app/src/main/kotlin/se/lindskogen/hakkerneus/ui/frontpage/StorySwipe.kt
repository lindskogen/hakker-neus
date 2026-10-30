package se.lindskogen.hakkerneus.ui.frontpage

import kotlin.math.abs

/**
 * Geometry of the story row swipe actions, the same numbers as the iOS `StorySwipe` (in dp).
 * Positive offsets drag the row right (save, then upvote when available), negative drag it
 * left (comments).
 */
data class StorySwipe(val offset: Float) {
    enum class Action { Save, Upvote, Comments }

    companion object {
        const val SAVE_THRESHOLD = 80f
        const val UPVOTE_THRESHOLD = 160f
        const val COMMENTS_THRESHOLD = 100f

        /** The row follows the finger up to the last threshold, then at a quarter of the speed. */
        fun forTranslation(translation: Float, canUpvote: Boolean): StorySwipe {
            val threshold = when {
                translation < 0 -> COMMENTS_THRESHOLD
                canUpvote -> UPVOTE_THRESHOLD
                else -> SAVE_THRESHOLD
            }
            val magnitude = abs(translation)
            val resisted = if (magnitude <= threshold) magnitude else threshold + (magnitude - threshold) / 4
            return StorySwipe(if (translation < 0) -resisted else resisted)
        }
    }

    fun armedAction(canUpvote: Boolean): Action? = when {
        canUpvote && offset >= UPVOTE_THRESHOLD -> Action.Upvote
        offset >= SAVE_THRESHOLD -> Action.Save
        offset <= -COMMENTS_THRESHOLD -> Action.Comments
        else -> null
    }

    /** Heart behind the left edge: slides in from -80 to 0 and fades in after the first 10. */
    val heartTranslation: Float get() = (offset - SAVE_THRESHOLD).coerceIn(-SAVE_THRESHOLD, 0f)
    val heartAlpha: Float get() = ((offset - 10) / (SAVE_THRESHOLD - 10)).coerceIn(0f, 1f)

    /** Comment count behind the right edge: grows to full size over the first 80. */
    val commentCountScale: Float get() = (-offset / 80).coerceIn(0f, 1f)
}
