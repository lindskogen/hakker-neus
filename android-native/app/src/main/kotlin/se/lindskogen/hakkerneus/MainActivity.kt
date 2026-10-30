package se.lindskogen.hakkerneus

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import se.lindskogen.hakkerneus.ui.AppNavigation
import se.lindskogen.hakkerneus.ui.theme.HakkerNeusTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // Edge to edge with light status bar icons over the orange.
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        setContent {
            HakkerNeusTheme { AppNavigation() }
        }
    }
}
