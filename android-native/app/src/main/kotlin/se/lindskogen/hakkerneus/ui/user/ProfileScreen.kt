package se.lindskogen.hakkerneus.ui.user

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.ui.ScrollToTop
import se.lindskogen.hakkerneus.ui.theme.HN

/**
 * The Profile place: your own HN page (your stories and comments) when signed in, or a way to
 * sign in. Follows who's signed in.
 */
@Composable
fun ProfileScreen(
    username: String?,
    openComments: (Story) -> Unit,
    openItem: (Long) -> Unit,
    openLink: (String) -> Unit,
    signIn: () -> Unit,
    scrollToTop: ScrollToTop?,
) {
    if (username == null) {
        SignedOutProfile(signIn)
    } else {
        UserScreen(username, openComments = openComments, openItem = openItem, openLink = openLink, signIn = signIn, scrollToTop = scrollToTop)
    }
}

@Composable
private fun SignedOutProfile(signIn: () -> Unit) {
    Box(Modifier.fillMaxSize().background(HN.backgroundDark), contentAlignment = Alignment.Center) {
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(20.dp),
            modifier = Modifier.padding(32.dp),
        ) {
            Text(
                "Sign in to see your stories and comments",
                style = HN.titleStyle().copy(fontSize = 24.sp, color = Color.White.copy(alpha = 0.6f)),
                textAlign = TextAlign.Center,
            )
            Button(onClick = signIn, colors = ButtonDefaults.buttonColors(containerColor = HN.accent, contentColor = Color.White)) {
                Text("Sign in")
            }
        }
    }
}
