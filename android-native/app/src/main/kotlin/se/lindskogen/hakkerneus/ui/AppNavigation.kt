package se.lindskogen.hakkerneus.ui

import se.lindskogen.hakkerneus.data.Lobsters
import se.lindskogen.hakkerneus.data.TopStoriesFeed
import se.lindskogen.hakkerneus.ui.frontpage.FeedMenuHooks
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Surface
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import se.lindskogen.hakkerneus.ui.comments.LobstersCommentsScreen
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.launch
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
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
import se.lindskogen.hakkerneus.ui.user.UserScreen
import se.lindskogen.hakkerneus.ui.theme.HN

@Serializable object FrontPage
@Serializable object Saved
@Serializable object Settings
@Serializable object Search
@Serializable object SignIn
@Serializable data class Compose(val parent: Long, val story: Long, val context: String)
@Serializable data class Comments(val id: Long)
@Serializable data class User(val name: String)

private enum class CornerMode { Profile, Back, Hidden }

@OptIn(ExperimentalSharedTransitionApi::class, ExperimentalFoundationApi::class)
@Composable
fun AppNavigation(pendingLink: MutableStateFlow<Uri?> = MutableStateFlow(null)) {
    val nav = rememberNavController()
    val context = LocalContext.current
    val link by pendingLink.collectAsState()

    // Opening comments or a user page waits briefly for the data (usually already prefetched on
    // touch down), so the screen opens filled instead of showing a loading state for a moment.
    // Gives up waiting after 150 ms; taps while waiting are ignored.
    val navScope = rememberCoroutineScope()
    val waiting = remember { booleanArrayOf(false) }
    fun navigateAfterBriefWait(route: Any, fetch: suspend () -> Unit) {
        if (waiting[0]) return
        waiting[0] = true
        navScope.launch {
            withTimeoutOrNull(150) {
                try {
                    fetch()
                } catch (e: CancellationException) {
                    throw e
                } catch (_: Exception) {
                    // The screen shows the error.
                }
            }
            waiting[0] = false
            nav.navigate(route)
        }
    }
    fun openComments(id: Long) = navigateAfterBriefWait(Comments(id)) {
        // A link to a comment opens its story; have that ready too.
        AppContainer.items.item(id).item.parentStoryId?.let { AppContainer.items.item(it) }
    }
    fun openUser(name: String) = navigateAfterBriefWait(User(name)) { AppContainer.users.firstPage(name) }
    // hakkerneus://item?id=…, hakkerneus://user?id=…, hakkerneus://open?url=… and HN item links (see the manifest).
    LaunchedEffect(link) {
        val uri = link ?: return@LaunchedEffect
        pendingLink.value = null
        val target = when {
            uri.scheme == "hakkerneus" && uri.host == "item" -> uri.getQueryParameter("id")
            uri.scheme == "hakkerneus" && uri.host == "open" -> uri.getQueryParameter("url")
            uri.scheme == "hakkerneus" && uri.host == "user" ->
                uri.getQueryParameter("id")?.let { openUser(it); return@LaunchedEffect }
            else -> uri.toString()
        } ?: return@LaunchedEffect
        target.toLongOrNull()?.let { openComments(it); return@LaunchedEffect }
        when (val parsed = HackerNewsLink.parse(target)) {
            is HackerNewsLink.Item -> openComments(parsed.id)
            is HackerNewsLink.User -> openUser(parsed.name)
            else -> if (uri.host == "open") context.openInBrowser(target)
        }
    }
    val entry by nav.currentBackStackEntryAsState()
    val mode = when {
        entry?.destination?.hasRoute<FrontPage>() == true -> CornerMode.Profile
        entry?.destination?.hasRoute<Saved>() == true -> CornerMode.Back
        else -> CornerMode.Hidden
    }
    // The feed at the root, switched in place from the corner button's menu.
    var feed by rememberSaveable { mutableStateOf(TopStoriesFeed.Source.Top) }
    val feedMenu = remember { FeedMenuHooks() }
    var menuOpen by remember { mutableStateOf(false) }
    var toast by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(toast) {
        if (toast != null) {
            delay(1500)
            toast = null
        }
    }
    fun feedName(source: TopStoriesFeed.Source) = when (source) {
        TopStoriesFeed.Source.Top -> "Top"
        TopStoriesFeed.Source.New -> "New"
        TopStoriesFeed.Source.Lobsters -> "lobste.rs"
    }

    Box(Modifier.fillMaxSize()) {
    CompositionLocalProvider(LocalOpenUser provides { name -> openUser(name) }) {
    SharedTransitionLayout {
    CompositionLocalProvider(LocalSharedTransitionScope provides this) {
    NavHost(nav, startDestination = FrontPage, modifier = Modifier.background(HN.backgroundDark)) {
        composable<FrontPage> {
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
            Crossfade(feed, label = "feed") { source ->
                FrontPageScreen(
                    openComments = { AppContainer.visited.markCommentsSeen(it); openComments(it.id) },
                    openItem = { openComments(it) },
                    signIn = { nav.navigate(SignIn) },
                    source = source,
                    menu = feedMenu,
                )
            }
            }
        }
        composable<Comments> { entry ->
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
                val id = entry.toRoute<Comments>().id
                if (Lobsters.isLobsters(id)) LobstersCommentsScreen(id, openItem = { openComments(it) }) else CommentsScreen(
                    entry.toRoute<Comments>().id,
                    openItem = { openComments(it) },
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
                    openComments = { AppContainer.visited.markCommentsSeen(it); openComments(it.id) },
                    openItem = { openComments(it) },
                    openSettings = { nav.navigate(Settings) },
                    openSearch = { nav.navigate(Search) },
                    signIn = { nav.navigate(SignIn) },
                )
            }
        }
        composable<Search> {
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
                se.lindskogen.hakkerneus.ui.search.SearchScreen(
                    openComments = { AppContainer.visited.markCommentsSeen(it); openComments(it.id) },
                    openLink = { url ->
                        when (val link = HackerNewsLink.parse(url)) {
                            is HackerNewsLink.Item -> openComments(link.id)
                            is HackerNewsLink.User -> openUser(link.name)
                            else -> context.openInBrowser(url)
                        }
                    },
                    signIn = { nav.navigate(SignIn) },
                )
            }
        }
        composable<User> { entry ->
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
                UserScreen(
                    entry.toRoute<User>().name,
                    openComments = { AppContainer.visited.markCommentsSeen(it); openComments(it.id) },
                    openItem = { openComments(it) },
                    openLink = { url ->
                        when (val link = HackerNewsLink.parse(url)) {
                            is HackerNewsLink.Item -> openComments(link.id)
                            is HackerNewsLink.User -> openUser(link.name)
                            else -> context.openInBrowser(url)
                        }
                    },
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
    }

        // One lower-right button (lower-left for left hands) above every screen, so it stays put
        // while they change underneath: on the feed a person, opening the profile, and held, the
        // feed menu; on the profile, back.
        val onLeft = AppContainer.cornerButtonOnLeft
        AnimatedVisibility(
            visible = mode != CornerMode.Hidden,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(if (onLeft) Alignment.BottomStart else Alignment.BottomEnd),
        ) {
            val haptics = LocalHapticFeedback.current
            Box(
                Modifier
                    .navigationBarsPadding()
                    .padding(start = if (onLeft) 20.dp else 0.dp, end = if (onLeft) 0.dp else 20.dp, bottom = HN.padding),
            ) {
                Surface(
                    shape = CircleShape,
                    color = Color(0xE6404040),
                    contentColor = Color.White,
                    shadowElevation = 6.dp,
                    modifier = Modifier
                        .size(52.dp)
                        .clip(CircleShape)
                        .combinedClickable(
                            onClickLabel = if (mode == CornerMode.Back) "Back" else "Profile and saved stories",
                            onClick = { if (mode == CornerMode.Back) nav.popBackStack() else nav.navigate(Saved) },
                            onLongClickLabel = if (mode == CornerMode.Profile) "Feeds and search" else null,
                            onLongClick = if (mode == CornerMode.Profile) {
                                { haptics.performHapticFeedback(HapticFeedbackType.LongPress); menuOpen = true }
                            } else null,
                        )
                        .semantics { contentDescription = if (mode == CornerMode.Back) "Back" else "Profile and saved stories" },
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Crossfade(mode == CornerMode.Back, label = "corner icon") { back ->
                            Icon(if (back) HnIcons.back else HnIcons.person, contentDescription = null, modifier = Modifier.size(24.dp))
                        }
                    }
                }
                DropdownMenu(expanded = menuOpen, onDismissRequest = { menuOpen = false }) {
                    for (source in TopStoriesFeed.Source.entries) {
                        DropdownMenuItem(
                            text = { Text(feedName(source)) },
                            leadingIcon = {
                                when (source) {
                                    TopStoriesFeed.Source.Top -> Icon(HnIcons.arrowUp, contentDescription = null)
                                    TopStoriesFeed.Source.New -> Icon(HnIcons.clock, contentDescription = null)
                                    TopStoriesFeed.Source.Lobsters -> Text("L", style = HN.body.copy(fontSize = 17.sp, fontWeight = FontWeight.Bold), modifier = Modifier.width(24.dp), textAlign = TextAlign.Center)
                                }
                            },
                            trailingIcon = { if (source == feed) Icon(HnIcons.check, contentDescription = "Showing") },
                            onClick = {
                                menuOpen = false
                                if (source != feed) {
                                    feed = source
                                    toast = feedName(source)
                                }
                            },
                        )
                    }
                    HorizontalDivider()
                    DropdownMenuItem(
                        text = { Text("Search") },
                        leadingIcon = { Icon(HnIcons.search, contentDescription = null) },
                        onClick = { menuOpen = false; nav.navigate(Search) },
                    )
                    if (feedMenu.canUndo) DropdownMenuItem(
                        text = { Text("Show hidden stories") },
                        leadingIcon = { Icon(HnIcons.eye, contentDescription = null) },
                        onClick = { menuOpen = false; feedMenu.undo() },
                    ) else if (feedMenu.hasRead) DropdownMenuItem(
                        text = { Text("Hide read stories") },
                        leadingIcon = { Icon(HnIcons.eyeSlash, contentDescription = null) },
                        onClick = { menuOpen = false; feedMenu.hide() },
                    )
                }
            }
        }

        // The feed just switched to, named for a moment at the top.
        AnimatedVisibility(
            visible = toast != null,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(Alignment.TopCenter).statusBarsPadding().padding(top = 8.dp),
        ) {
            Text(
                toast ?: "",
                style = HN.body.copy(fontSize = 15.sp, fontWeight = FontWeight.Medium, color = Color.White),
                modifier = Modifier
                    .clip(RoundedCornerShape(17.dp))
                    .background(Color(0xD9141414))
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            )
        }
    }
}
