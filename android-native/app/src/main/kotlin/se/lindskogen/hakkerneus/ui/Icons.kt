package se.lindskogen.hakkerneus.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.unit.dp

/** The RN app's SVG icons (Icons.tsx) plus a couple more, as Compose vectors. */
object HnIcons {
    val heart = icon("M12 21a1 1 0 01-.71-.29l-7.77-7.78a5.26 5.26 0 010-7.4 5.24 5.24 0 017.4 0L12 6.61l1.08-1.08a5.24 5.24 0 017.4 0 5.26 5.26 0 010 7.4l-7.77 7.78A1 1 0 0112 21z")
    val heartBroken = icon("M12 21a1 1 0 01-.71-.29l-7.77-7.78a5.26 5.26 0 010-7.4 5.24 5.24 0 017.4 0L12 6.61l-1.5 3.39 2.5 1.5-2 4 4-5-2.5-1.5 1.58-3.47a5.24 5.24 0 017.4 0 5.26 5.26 0 010 7.4l-7.77 7.78A1 1 0 0112 21z")
    val menu = icon("M3 6h18v2H3zm0 5h18v2H3zm0 5h18v2H3z")
    val close = icon("M19 6.41 17.59 5 12 10.59 6.41 5 5 6.41 10.59 12 5 17.59 6.41 19 12 13.41 17.59 19 19 17.59 13.41 12z")
    val arrowUp = icon("M12 4l-7 7h4.5v9h5v-9H19z")
    val bubble = icon("M2 15V5c0-1.1.9-2 2-2h16a2 2 0 0 1 2 2v15a1 1 0 0 1-1.7.7L16.58 17H4a2 2 0 0 1-2-2zM20 5H4v10h13a1 1 0 0 1 .7.3l2.3 2.29V5z")
    val error = icon("M4.93 19.07A10 10 0 1 1 19.07 4.93 10 10 0 0 1 4.93 19.07zm1.41-1.41A8 8 0 1 0 17.66 6.34 8 8 0 0 0 6.34 17.66zM13.41 12l1.42 1.41a1 1 0 1 1-1.42 1.42L12 13.4l-1.41 1.42a1 1 0 1 1-1.42-1.42L10.6 12l-1.42-1.41a1 1 0 1 1 1.42-1.42L12 10.6l1.41-1.42a1 1 0 1 1 1.42 1.42L13.4 12z")

    private fun icon(path: String) = ImageVector.Builder(defaultWidth = 24.dp, defaultHeight = 24.dp, viewportWidth = 24f, viewportHeight = 24f)
        .addPath(PathParser().parsePathString(path).toNodes(), fill = SolidColor(Color.White))
        .build()
}
