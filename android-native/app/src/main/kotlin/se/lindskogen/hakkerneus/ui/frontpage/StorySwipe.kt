package se.lindskogen.hakkerneus.ui.frontpage

import kotlin.math.abs

/**
 * Geometry of the story row swipe actions, the same numbers as the iOS `StorySwipe` (in dp).
 * Positive offsets drag the row right (save, then upvote when available), negative drag it
 * left (comments).
 */
data class StorySwipe(
    val offset: Float,
    /** How far right toggles saved: [SAVE_THRESHOLD], or [UNSAVE_THRESHOLD] in the saved list. */
    val saveDistance: Float = SAVE_THRESHOLD,
) {
    enum class Action { Save, Upvote, Comments }

    companion object {
        const val SAVE_THRESHOLD = 80f
        /** In the saved list, where a swipe right only unsaves: this far, so it's never by accident. */
        const val UNSAVE_THRESHOLD = 160f
        const val UPVOTE_THRESHOLD = 160f
        const val COMMENTS_THRESHOLD = 80f

        /** The row follows the finger up to the last threshold, then at a quarter of the speed. */
        fun forTranslation(translation: Float, canUpvote: Boolean, saveDistance: Float = SAVE_THRESHOLD): StorySwipe {
            val threshold = when {
                translation < 0 -> COMMENTS_THRESHOLD
                canUpvote -> UPVOTE_THRESHOLD
                else -> saveDistance
            }
            val magnitude = abs(translation)
            val resisted = if (magnitude <= threshold) magnitude else threshold + (magnitude - threshold) / 4
            return StorySwipe(if (translation < 0) -resisted else resisted, saveDistance)
        }
    }

    fun armedAction(canUpvote: Boolean): Action? = when {
        canUpvote && offset >= UPVOTE_THRESHOLD -> Action.Upvote
        offset >= saveDistance -> Action.Save
        offset <= -COMMENTS_THRESHOLD -> Action.Comments
        else -> null
    }

    /**
     * The action that fires when the finger lifts: the armed one, or the comments for a flick left
     * that would coast past the threshold, to [projected] (where it would come to rest).
     */
    fun releasedAction(canUpvote: Boolean, projected: Float): Action? = armedAction(canUpvote)
        ?: if (projected <= -COMMENTS_THRESHOLD) Action.Comments else null

    /** Heart behind the left edge: slides in from -80 to 0 over the last 80 before saving, and fades in from the first 10. */
    val heartTranslation: Float get() = (offset - saveDistance).coerceIn(-SAVE_THRESHOLD, 0f)
    val heartAlpha: Float get() = ((offset - 10) / (saveDistance - 10)).coerceIn(0f, 1f)

    /** Comment count behind the right edge: grows to full size over the first 80. */
    val commentCountScale: Float get() = (-offset / 80).coerceIn(0f, 1f)
}
