package se.lindskogen.hakkerneus.ui

import androidx.compose.animation.Crossfade
import androidx.compose.animation.ExperimentalSharedTransitionApi
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.SmallFloatingActionButton
import androidx.compose.runtime.getValue
import androidx.compose.ui.draw.rotate
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.compose.currentBackStackEntryAsState
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
import android.net.Uri
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.serialization.Serializable
import se.lindskogen.hakkerneus.data.HackerNewsLink
import androidx.navigation.toRoute
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.ui.comments.CommentsScreen
import androidx.compose.runtime.collectAsState
import se.lindskogen.hakkerneus.account.ComposeScreen
import se.lindskogen.hakkerneus.account.SignInScreen
import se.lindskogen.hakkerneus.ui.frontpage.FrontPageScreen
import se.lindskogen.hakkerneus.ui.settings.AccountSection
import se.lindskogen.hakkerneus.ui.saved.SavedScreen
import se.lindskogen.hakkerneus.ui.settings.SettingsScreen
import se.lindskogen.hakkerneus.ui.theme.HN

@Serializable object FrontPage
@Serializable object Saved
@Serializable object Settings
@Serializable object SignIn
@Serializable data class Compose(val parent: Long, val story: Long, val context: String)
@Serializable data class Comments(val id: Long)

private enum class CornerMode { Menu, Close, Hidden }

@OptIn(ExperimentalSharedTransitionApi::class)
@Composable
fun AppNavigation(pendingLink: MutableStateFlow<Uri?> = MutableStateFlow(null)) {
    val nav = rememberNavController()
    val context = LocalContext.current
    val link by pendingLink.collectAsState()
    // hakkerneus://item?id=…, hakkerneus://open?url=… and HN item links (see the manifest).
    LaunchedEffect(link) {
        val uri = link ?: return@LaunchedEffect
        pendingLink.value = null
        val target = when {
            uri.scheme == "hakkerneus" && uri.host == "item" -> uri.getQueryParameter("id")
            uri.scheme == "hakkerneus" && uri.host == "open" -> uri.getQueryParameter("url")
            else -> uri.toString()
        } ?: return@LaunchedEffect
        target.toLongOrNull()?.let { nav.navigate(Comments(it)); return@LaunchedEffect }
        when (val parsed = HackerNewsLink.parse(target)) {
            is HackerNewsLink.Item -> nav.navigate(Comments(parsed.id))
            else -> if (uri.host == "open") context.openInBrowser(target)
        }
    }
    val entry by nav.currentBackStackEntryAsState()
    val mode = when {
        entry?.destination?.hasRoute<FrontPage>() == true -> CornerMode.Menu
        entry?.destination?.hasRoute<Saved>() == true -> CornerMode.Close
        else -> CornerMode.Hidden
    }

    Box(Modifier.fillMaxSize()) {
    SharedTransitionLayout {
    CompositionLocalProvider(LocalSharedTransitionScope provides this) {
    NavHost(nav, startDestination = FrontPage, modifier = Modifier.background(HN.backgroundDark)) {
        composable<FrontPage> {
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
            FrontPageScreen(
                openComments = { AppContainer.visited.markCommentsSeen(it); nav.navigate(Comments(it.id)) },
                openItem = { nav.navigate(Comments(it)) },
                signIn = { nav.navigate(SignIn) },
            )
            }
        }
        composable<Comments> { entry ->
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
                CommentsScreen(
                    entry.toRoute<Comments>().id,
                    openItem = { nav.navigate(Comments(it)) },
                    compose = { parent, story, context ->
                        val open = { nav.navigate(Compose(parent, story, context)) }
                        if (AppContainer.session.isSignedIn) open() else { AppContainer.afterSignIn = open; nav.navigate(SignIn) }
                    },
                    signIn = { nav.navigate(SignIn) },
                )
            }
        }
        composable<Saved> {
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
                val username by AppContainer.session.username.collectAsState()
                SavedScreen(
                    username = username,
                    openComments = { AppContainer.visited.markCommentsSeen(it); nav.navigate(Comments(it.id)) },
                    openItem = { nav.navigate(Comments(it)) },
                    openSettings = { nav.navigate(Settings) },
                    signIn = { nav.navigate(SignIn) },
                )
            }
        }
        composable<Settings> {
            SettingsScreen(back = { nav.popBackStack() }, account = { AccountSection(signIn = { nav.navigate(SignIn) }) })
        }
        composable<SignIn> {
            SignInScreen(done = { nav.popBackStack() })
        }
        composable<Compose> { entry ->
            val route = entry.toRoute<Compose>()
            ComposeScreen(route.parent, route.story, route.context, done = { nav.popBackStack() })
        }
    }
    }
    }

        // One lower-right button (lower-left for left hands) above every screen, so it stays put
        // while they change underneath: the hamburger on the front page opens the profile, the
        // close button returns.
        val onLeft = AppContainer.cornerButtonOnLeft
        AnimatedVisibility(
            visible = mode != CornerMode.Hidden,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(if (onLeft) Alignment.BottomStart else Alignment.BottomEnd),
        ) {
            SmallFloatingActionButton(
                onClick = { if (mode == CornerMode.Close) nav.popBackStack() else nav.navigate(Saved) },
                shape = CircleShape,
                containerColor = Color(0xE6404040),
                contentColor = Color.White,
                modifier = Modifier
                    .navigationBarsPadding()
                    .padding(start = if (onLeft) 20.dp else 0.dp, end = if (onLeft) 0.dp else 20.dp, bottom = HN.padding)
                    .size(52.dp)
                    .semantics { contentDescription = if (mode == CornerMode.Close) "Front page" else "Profile and saved stories" },
            ) {
                // The icon turns between the hamburger and the close button: the hamburger rotates
                // a quarter turn as it fades out, the close button rotates into place as it fades in.
                val isClose = mode == CornerMode.Close
                val turn by animateFloatAsState(if (isClose) 90f else 0f, label = "corner turn")
                Crossfade(isClose, label = "corner icon") { close ->
                    Icon(
                        if (close) HnIcons.close else HnIcons.menu,
                        contentDescription = null,
                        modifier = Modifier.size(22.dp).rotate(if (close) turn - 90f else turn),
                    )
                }
            }
        }
    }
}
