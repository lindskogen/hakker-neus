package se.lindskogen.hakkerneus.ui.theme

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** Port of `src/common/vars.ts` and the iOS `Theme`. */
object HN {
    val padding = 10.dp
    val backgroundDark = Color(0xFF1B1D21)
    val backgroundRed = Color(0xFFCE5B4C)
    val backgroundOrange = Palette.orangesRgb(0.65).color

    /** Story titles. No Helvetica Neue on Android: light sans-serif, as the RN app used here. */
    fun titleStyle(isTablet: Boolean = false) = TextStyle(
        fontFamily = FontFamily.SansSerif,
        fontWeight = FontWeight.Light,
        fontSize = if (isTablet) 30.sp else 25.sp,
        lineHeight = if (isTablet) 36.sp else 30.sp,
        color = Color.White,
    )

    val body = TextStyle(fontFamily = FontFamily.SansSerif, fontSize = 16.sp, lineHeight = 22.sp, color = Color.White)
}

private val colors = darkColorScheme(
    primary = HN.backgroundOrange,
    background = HN.backgroundDark,
    surface = HN.backgroundDark,
    onPrimary = Color.White,
    onBackground = Color.White,
    onSurface = Color.White,
)

@Composable
fun HakkerNeusTheme(content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = colors, content = content)
}
