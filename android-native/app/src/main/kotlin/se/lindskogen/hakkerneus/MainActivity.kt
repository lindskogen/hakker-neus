package se.lindskogen.hakkerneus

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import kotlinx.coroutines.flow.MutableStateFlow
import se.lindskogen.hakkerneus.ui.AppNavigation
import se.lindskogen.hakkerneus.ui.theme.HakkerNeusTheme

class MainActivity : ComponentActivity() {
    /** A link the app was opened with, until AppNavigation has followed it. */
    private val pendingLink = MutableStateFlow<Uri?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) pendingLink.value = intent?.data
        // Edge to edge with light status bar icons over the orange.
        enableEdgeToEdge(statusBarStyle = SystemBarStyle.dark(android.graphics.Color.TRANSPARENT))
        super.onCreate(savedInstanceState)
        setContent {
            HakkerNeusTheme { AppNavigation(pendingLink) }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.data?.let { pendingLink.value = it }
    }
}
