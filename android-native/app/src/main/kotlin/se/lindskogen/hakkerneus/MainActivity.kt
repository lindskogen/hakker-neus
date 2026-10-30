package se.lindskogen.hakkerneus

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.HakkerNeusTheme
import se.lindskogen.hakkerneus.ui.theme.Palette

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge to edge with light status bar icons over the orange.
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        setContent {
            HakkerNeusTheme { PaletteCheck() }
        }
    }
}

/** Placeholder until the front page lands in A2: the row colour ramp. */
@Composable
private fun PaletteCheck() {
    Column(Modifier.fillMaxSize().background(Palette.storyBackground(0))) {
        Box(Modifier.statusBarsPadding())
        for (index in 0 until 8) {
            Box(
                Modifier
                    .fillMaxWidth()
                    .heightIn(min = 100.dp)
                    .background(Palette.storyBackground(index))
                    .padding(horizontal = HN.padding, vertical = 20.dp),
            ) {
                Text("HakkerNeus row $index", style = HN.titleStyle())
            }
        }
    }
}
