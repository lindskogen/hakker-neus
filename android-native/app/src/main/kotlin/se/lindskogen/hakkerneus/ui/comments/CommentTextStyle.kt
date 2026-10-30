package se.lindskogen.hakkerneus.ui.comments

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Comment (and self-post) text: its size, and whether code blocks wrap or scroll sideways. As on iOS. */
object CommentTextStyle {
    /** Body text size; medium is the original 16. Code is set 2sp smaller. */
    enum class Size(val title: String, val points: Int) {
        Small("Small", 14), Medium("Medium", 16), Large("Large", 18);

        val codePoints get() = points - 2
    }

    /** Compose state, so open comments follow a change. Set via AppContainer, which saves it. */
    var wrapsLines by mutableStateOf(false)
    var size by mutableStateOf(Size.Medium)
}
