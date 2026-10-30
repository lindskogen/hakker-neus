package se.lindskogen.hakkerneus.ui.comments

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Code blocks in comments: unwrapped (scrolling sideways) or wrapped, and their text size. As on iOS. */
object CodeBlockStyle {
    enum class Size(val title: String, val sp: Int) { Small("Small", 12), Medium("Medium", 14), Large("Large", 16) }

    /** Compose state, so open comments follow a change. Set via AppContainer, which saves it. */
    var wrapsLines by mutableStateOf(false)
    var size by mutableStateOf(Size.Medium)
}
