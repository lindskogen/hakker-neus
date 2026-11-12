package se.lindskogen.hakkerneus.ui

import se.lindskogen.hakkerneus.data.Lobsters
import se.lindskogen.hakkerneus.data.TopStoriesFeed
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.lazy.LazyListState
import se.lindskogen.hakkerneus.ui.frontpage.HideReadHooks
import se.lindskogen.hakkerneus.ui.frontpage.LobstersFrontPageScreen
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.material3.Surface
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
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
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.getValue
import androidx.compose.runtime.setValue
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.navigation.NavDestination.Companion.hasRoute
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
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
import se.lindskogen.hakkerneus.ui.user.ProfileScreen
import se.lindskogen.hakkerneus.ui.user.UserScreen
import se.lindskogen.hakkerneus.ui.theme.HN
import se.lindskogen.hakkerneus.ui.theme.Palette
import androidx.lifecycle.viewmodel.compose.viewModel

@Serializable object FrontPage
@Serializable object Saved
@Serializable object Settings
@Serializable object Search
@Serializable object SignIn
@Serializable data class Compose(val parent: Long, val story: Long, val context: String)
@Serializable data class Comments(val id: Long)
@Serializable data class User(val name: String)

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
    // On a top-level place (a feed, Saved or Search), not on something opened from one.
    val atTop = entry?.destination?.hasRoute<FrontPage>() == true
    // The place showing, picked in the sidebar. The app starts at its site's first feed.
    var place by rememberSaveable { mutableStateOf(Place.home(AppContainer.site)) }
    // Each feed's read stories, for the hide-read button above the corner button.
    val hideRead = remember { TopStoriesFeed.Source.entries.associateWith { HideReadHooks() } }
    val scrollToTop = remember { Place.entries.associateWith { ScrollToTop() } }
    val savedList = rememberSaveable(saver = LazyListState.Saver) { LazyListState() }
    val sidebar = remember { SidebarState() }
    // Screens left with back, and the browser, for the forward swipe from the right edge.
    val forward: ForwardHistory = viewModel()
    LaunchedEffect(nav) { nav.currentBackStack.collect(forward::backStackChanged) }
    LaunchedEffect(Unit) { browserOpened.collect(forward::browserOpened) }
    // Forward goes on from a top-level place or what was opened from one, not from Settings and the like.
    val canGoForward = forward.next != null && !sidebar.isOpen && entry?.destination?.let {
        it.hasRoute<FrontPage>() || it.hasRoute<Comments>() || it.hasRoute<User>()
    } == true
    fun goForward() = forward.goForward(nav) { context.openInBrowser(it) }

    /** Goes to [to], making the app about its site if it's the other one. */
    fun go(to: Place) {
        to.site?.takeIf { it != AppContainer.site }?.let(AppContainer::switchSite)
        place = to
        navScope.launch { sidebar.close() }
    }
    // Back from another place goes to the site's first feed, then out of the app.
    BackHandler(enabled = atTop && place != Place.home(AppContainer.site)) { go(Place.home(AppContainer.site)) }

    SidebarLayout(
        sidebar,
        enabled = atTop,
        accent = if (AppContainer.site == Site.HackerNews) HN.accent else Palette.lobstersAccent,
        sidebar = {
            val username by AppContainer.session.username.collectAsState()
            SidebarPlaces(here = place, username = username, go = ::go, openSettings = {
                navScope.launch { sidebar.close() }
                nav.navigate(Settings)
            })
        },
    ) {
    ForwardSwipeLayout(enabled = canGoForward, onForward = ::goForward) {
    Box(Modifier.fillMaxSize()) {
    CompositionLocalProvider(LocalOpenUser provides { name -> openUser(name) }) {
    SharedTransitionLayout {
    CompositionLocalProvider(LocalSharedTransitionScope provides this) {
    NavHost(nav, startDestination = FrontPage, modifier = Modifier.background(HN.backgroundDark)) {
        composable<FrontPage> {
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
                Crossfade(place, label = "place") { here ->
                    PlaceScreen(
                        here,
                        openComments = { AppContainer.visited.markCommentsSeen(it); openComments(it.id) },
                        openItem = { openComments(it) },
                        openUser = { openUser(it) },
                        signIn = { nav.navigate(SignIn) },
                        hideRead = hideRead,
                        savedList = savedList,
                        scrollToTop = scrollToTop.getValue(here),
                    )
                }
            }
        }
        composable<Comments> { entry ->
            KeptViewModels(forward, entry) {
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
        }
        composable<User> { entry ->
            KeptViewModels(forward, entry) {
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

        // The corner button shows once the place is scrolled down more than half a screen (always
        // with TalkBack, where it also holds the actions for the sidebar and going forward).
        val touchExploration = rememberTouchExploration()
        val showsCorner = atTop && (touchExploration || scrollToTop.getValue(place).isScrolledDown)

        // Above the corner button on a feed: hide the read stories (an eye with a slash) or, after
        // hiding, show them again (an eye). Hiding wins: reading another story brings the slash
        // back.
        val feedHooks = place.feed?.let(hideRead::getValue) ?: HideReadHooks()
        val hides = feedHooks.hasRead
        val offersHide = atTop && place.feed != null && (hides || feedHooks.canUndo)
        // Keeps its icon while fading out.
        var showsHide by remember { mutableStateOf(true) }
        if (offersHide) showsHide = hides
        AnimatedVisibility(
            visible = offersHide,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(if (AppContainer.cornerButtonOnLeft) Alignment.BottomStart else Alignment.BottomEnd),
        ) {
            val onLeft = AppContainer.cornerButtonOnLeft
            // Centred over the 52dp corner button, 12dp above it; in its place while it's hidden.
            val inset = 20.dp + (52.dp - 42.dp) / 2
            val bottom by animateDpAsState(
                if (showsCorner) HN.padding + 52.dp + 12.dp else HN.padding + (52.dp - 42.dp) / 2,
                label = "hide-read position",
            )
            Box(
                Modifier
                    .navigationBarsPadding()
                    .padding(start = if (onLeft) inset else 0.dp, end = if (onLeft) 0.dp else inset, bottom = bottom),
            ) {
                val label = if (showsHide) "Hide read stories" else "Show hidden stories"
                Surface(
                    onClick = { if (showsHide) feedHooks.hide() else feedHooks.undo() },
                    shape = CircleShape,
                    color = Color(0xE6404040),
                    contentColor = Color.White,
                    shadowElevation = 6.dp,
                    modifier = Modifier.size(42.dp).semantics { contentDescription = label },
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Crossfade(showsHide, label = "hide-read icon") { hide ->
                            Icon(if (hide) HnIcons.eyeSlash else HnIcons.eye, contentDescription = null, modifier = Modifier.size(20.dp))
                        }
                    }
                }
            }
        }

        // One lower-right button (lower-left for left hands) on the top-level places, scrolling
        // the one showing to the top.
        val onLeft = AppContainer.cornerButtonOnLeft
        AnimatedVisibility(
            visible = showsCorner,
            enter = fadeIn() + scaleIn(initialScale = 0.6f),
            exit = fadeOut() + scaleOut(targetScale = 0.6f),
            modifier = Modifier.align(if (onLeft) Alignment.BottomStart else Alignment.BottomEnd),
        ) {
            Box(
                Modifier
                    .navigationBarsPadding()
                    .padding(start = if (onLeft) 20.dp else 0.dp, end = if (onLeft) 0.dp else 20.dp, bottom = HN.padding),
            ) {
                Surface(
                    onClick = { navScope.launch { scrollToTop.getValue(place).scroll() } },
                    shape = CircleShape,
                    color = Color(0xE6404040),
                    contentColor = Color.White,
                    shadowElevation = 6.dp,
                    modifier = Modifier
                        .size(52.dp)
                        .semantics {
                            contentDescription = "Scroll to top"
                            // The sidebar opens with a swipe from the edge; here it's an action too.
                            customActions = listOfNotNull(
                                CustomAccessibilityAction("Open menu") { navScope.launch { sidebar.open() }; true },
                                // Forward is a swipe from the other edge.
                                forward.next?.let { CustomAccessibilityAction("Go forward") { goForward(); true } },
                            )
                        },
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(HnIcons.arrowUp, contentDescription = null, modifier = Modifier.size(24.dp))
                    }
                }
            }
        }
    }
    }
    }
}

/** A top-level place's screen. */
@Composable
private fun PlaceScreen(
    place: Place,
    openComments: (se.lindskogen.hakkerneus.data.Story) -> Unit,
    openItem: (Long) -> Unit,
    openUser: (String) -> Unit,
    signIn: () -> Unit,
    hideRead: Map<TopStoriesFeed.Source, HideReadHooks>,
    savedList: LazyListState,
    scrollToTop: ScrollToTop,
) {
    val context = LocalContext.current
    when (place) {
        Place.Top, Place.New -> FrontPageScreen(
            openComments = openComments, openItem = openItem, signIn = signIn,
            source = place.feed!!, menu = hideRead.getValue(place.feed), scrollToTop = scrollToTop,
        )
        Place.Hottest, Place.Newest -> LobstersFrontPageScreen(
            openComments = openComments, openItem = openItem,
            source = place.feed!!, menu = hideRead.getValue(place.feed), scrollToTop = scrollToTop,
        )
        Place.Profile -> {
            val username by AppContainer.session.username.collectAsState()
            ProfileScreen(
                username = username,
                openComments = openComments,
                openItem = openItem,
                openLink = { url ->
                    when (val link = HackerNewsLink.parse(url)) {
                        is HackerNewsLink.Item -> openItem(link.id)
                        is HackerNewsLink.User -> openUser(link.name)
                        else -> context.openInBrowser(url)
                    }
                },
                signIn = signIn,
                scrollToTop = scrollToTop,
            )
        }
        Place.Saved -> {
            SavedScreen(
                openComments = openComments,
                openItem = openItem,
                signIn = signIn,
                listState = savedList,
                scrollToTop = scrollToTop,
            )
        }
        Place.Search -> se.lindskogen.hakkerneus.ui.search.SearchScreen(
            openComments = openComments,
            openLink = { url ->
                when (val link = HackerNewsLink.parse(url)) {
                    is HackerNewsLink.Item -> openItem(link.id)
                    is HackerNewsLink.User -> openUser(link.name)
                    else -> context.openInBrowser(url)
                }
            },
            signIn = signIn,
            scrollToTop = scrollToTop,
        )
    }
}
