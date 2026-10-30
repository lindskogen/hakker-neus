package se.lindskogen.hakkerneus.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import kotlinx.serialization.Serializable
import androidx.navigation.toRoute
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.ui.frontpage.CornerButton
import se.lindskogen.hakkerneus.ui.frontpage.FrontPageScreen
import se.lindskogen.hakkerneus.ui.theme.HN

@Serializable object FrontPage
@Serializable object Saved
@Serializable data class Comments(val id: Long)

@Composable
fun AppNavigation() {
    val nav = rememberNavController()
    NavHost(nav, startDestination = FrontPage, modifier = Modifier.background(HN.backgroundDark)) {
        composable<FrontPage> {
            FrontPageScreen(
                openComments = { nav.navigate(Comments(it.id)) },
                openItem = { nav.navigate(Comments(it)) },
                openSaved = { nav.navigate(Saved) },
            )
        }
        composable<Comments> { entry ->
            val id = entry.toRoute<Comments>().id
            Placeholder(AppContainer.knownStories[id]?.title ?: "Item $id", "Comments arrive in A3.")
        }
        composable<Saved> {
            Box(Modifier.fillMaxSize()) {
                Placeholder("Saved stories", "The saved list and profile arrive in A4.")
                // Same place as the front page's menu button: back to the front page.
                CornerButton(HnIcons.close, "Front page", { nav.popBackStack() }, Modifier.align(Alignment.BottomStart))
            }
        }
    }
}

@Composable
private fun Placeholder(title: String, detail: String) {
    Column(Modifier.fillMaxSize().background(HN.backgroundDark)) {
        Box(Modifier.fillMaxWidth().background(HN.backgroundOrange).statusBarsPadding().padding(HN.padding, 20.dp)) {
            Text(title, style = HN.titleStyle())
        }
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(detail, style = HN.body.copy(color = Color.White.copy(alpha = 0.4f)))
        }
    }
}
