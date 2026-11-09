package se.lindskogen.hakkerneus.ui

import se.lindskogen.hakkerneus.data.Lobsters
import se.lindskogen.hakkerneus.data.TopStoriesFeed
import se.lindskogen.hakkerneus.ui.frontpage.HideReadHooks
import se.lindskogen.hakkerneus.ui.frontpage.LobstersFrontPageScreen
import se.lindskogen.hakkerneus.ui.reel.ReelOverlay
import se.lindskogen.hakkerneus.ui.reel.ReelSite
import se.lindskogen.hakkerneus.ui.reel.ReelState
import se.lindskogen.hakkerneus.ui.reel.hnReel
import se.lindskogen.hakkerneus.ui.reel.lobstersReel
import se.lindskogen.hakkerneus.ui.reel.reelGesture
import android.animation.ValueAnimator
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.ClipOp
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.clipPath
import androidx.compose.ui.graphics.layer.drawLayer
import androidx.compose.ui.graphics.rememberGraphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.role
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.material3.Surface
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.draw.clip
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.unit.sp
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
    // The site the app is about, and the feed showing at the root for each, switched from the reel.
    val site = AppContainer.site
    var hnFeed by rememberSaveable { mutableStateOf(TopStoriesFeed.Source.Top) }
    var lobstersFeed by rememberSaveable { mutableStateOf(TopStoriesFeed.Source.LobstersHottest) }
    fun feedOf(site: Site) = if (site == Site.HackerNews) hnFeed else lobstersFeed
    // Each feed's read stories, for the hide-read button above the corner button.
    val hideRead = remember { TopStoriesFeed.Source.entries.associateWith { HideReadHooks() } }
    val reel = remember { ReelState() }

    // Switching site floods the new site's screen out from the finger: a snapshot of the old one
    // is drawn on top with a growing hole in it. With animations off, it fades instead.
    val screens = rememberGraphicsLayer()
    var flood by remember { mutableStateOf<Flood?>(null) }
    val floodProgress = remember { Animatable(0f) }
    fun switchSite(to: Site, from: Offset, then: () -> Unit) {
        navScope.launch {
            val snapshot = runCatching { screens.toImageBitmap() }.getOrNull()
            flood = snapshot?.let { Flood(it, from, circle = ValueAnimator.areAnimatorsEnabled()) }
            AppContainer.switchSite(to)
            then()
            if (snapshot != null) {
                floodProgress.snapTo(0f)
                floodProgress.animateTo(1f, tween(450, easing = FastOutSlowInEasing))
            }
            flood = null
        }
    }
    /** Goes to [place] on [target], switching site first if it's the other one. */
    fun go(target: Site, place: Place, from: Offset) {
        val arrive = {
            when (place) {
                Place.Top, Place.New -> hnFeed = place.feed!!
                Place.Hottest, Place.Newest -> lobstersFeed = place.feed!!
                Place.Saved -> nav.navigate(Saved)
                Place.Search -> nav.navigate(Search)
            }
        }
        if (target == AppContainer.site) arrive() else switchSite(target, from, arrive)
    }
    /** The current site's reel, and the other site's, as they are now. */
    fun reelSites(): Pair<ReelSite, ReelSite> = when (AppContainer.site) {
        Site.HackerNews -> hnReel(Place.of(hnFeed)) to lobstersReel(here = null)
        Site.Lobsters -> lobstersReel(Place.of(lobstersFeed)) to hnReel(here = null)
    }

    Box(Modifier.fillMaxSize().onGloballyPositioned { reel.origin = it.positionInRoot() }) {
    Box(Modifier.fillMaxSize().drawWithContent {
        screens.record { this@drawWithContent.drawContent() }
        drawLayer(screens)
    }) {
    CompositionLocalProvider(LocalOpenUser provides { name -> openUser(name) }) {
    SharedTransitionLayout {
    CompositionLocalProvider(LocalSharedTransitionScope provides this) {
    NavHost(nav, startDestination = FrontPage, modifier = Modifier.background(HN.backgroundDark)) {
        composable<FrontPage> {
            CompositionLocalProvider(LocalNavAnimatedScope provides this) {
                when (site) {
                    Site.HackerNews -> Crossfade(hnFeed, label = "feed") { source ->
                        FrontPageScreen(
                            openComments = { AppContainer.visited.markCommentsSeen(it); openComments(it.id) },
                            openItem = { openComments(it) },
                            signIn = { nav.navigate(SignIn) },
                            source = source,
                            menu = hideRead.getValue(source),
                        )
                    }
                    Site.Lobsters -> Crossfade(lobstersFeed, label = "lobste.rs feed") { source ->
                        LobstersFrontPageScreen(
                            openComments = { AppContainer.visited.markCommentsSeen(it); openComments(it.id) },
                            openItem = { openComments(it) },
                            source = source,
                            menu = hideRead.getValue(source),
                        )
                    }
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
    }

        // The old site's screen, with the new one showing through a growing hole.
        flood?.let { current ->
            Canvas(Modifier.fillMaxSize()) {
                if (current.circle) {
                    val radius = floodProgress.value * maxOf(
                        (current.center - Offset.Zero).getDistance(), (current.center - Offset(size.width, 0f)).getDistance(),
                        (current.center - Offset(0f, size.height)).getDistance(), (current.center - Offset(size.width, size.height)).getDistance(),
                    )
                    val hole = Path().apply { addOval(Rect(current.center, radius)) }
                    clipPath(hole, ClipOp.Difference) { drawImage(current.image) }
                    drawCircle(Color.White.copy(alpha = 0.12f * (1f - floodProgress.value)), radius, current.center, style = Stroke(6.dp.toPx()))
                } else {
                    drawImage(current.image, alpha = 1f - floodProgress.value)
                }
            }
        }

        ReelOverlay(reel)

        // Above the corner button on a feed: hide the read stories (an eye with a slash) or, after
        // hiding, show them again (an eye). Hiding wins: reading another story brings the slash
        // back. Out of the way while the reel is open.
        val onFeed = mode == CornerMode.Profile
        val feedHooks = hideRead.getValue(feedOf(site))
        val hides = feedHooks.hasRead
        val offersHide = onFeed && !reel.isOpen && (hides || feedHooks.canUndo)
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
            // Centred over the 52dp corner button, 12dp above it.
            val inset = 20.dp + (52.dp - 42.dp) / 2
            Box(
                Modifier
                    .navigationBarsPadding()
                    .padding(start = if (onLeft) inset else 0.dp, end = if (onLeft) 0.dp else inset, bottom = HN.padding + 52.dp + 12.dp),
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

        // One lower-right button (lower-left for left hands) above every screen, so it stays put
        // while they change underneath: on the feed a person, opening the profile, and dragged up
        // or held, the reel; on the profile, back.
        val onLeft = AppContainer.cornerButtonOnLeft
        reel.onLeft = onLeft
        AnimatedVisibility(
            visible = mode != CornerMode.Hidden,
            enter = fadeIn(),
            exit = fadeOut(),
            modifier = Modifier.align(if (onLeft) Alignment.BottomStart else Alignment.BottomEnd),
        ) {
            val haptics = LocalHapticFeedback.current
            var pressed by remember { mutableStateOf(false) }
            val currentMode by rememberUpdatedState(mode)
            Box(
                Modifier
                    .navigationBarsPadding()
                    .padding(start = if (onLeft) 20.dp else 0.dp, end = if (onLeft) 0.dp else 20.dp, bottom = HN.padding),
            ) {
                Surface(
                    shape = CircleShape,
                    color = if (pressed) Color(0xF0585858) else Color(0xE6404040),
                    contentColor = Color.White,
                    shadowElevation = 6.dp,
                    modifier = Modifier
                        .size(52.dp)
                        .onGloballyPositioned { reel.button = it.boundsInRoot() }
                        .pointerInput(Unit) {
                            reelGesture(
                                reel, haptics,
                                sites = ::reelSites,
                                pressed = { pressed = it },
                                onTap = { if (currentMode == CornerMode.Back) nav.popBackStack() else if (currentMode == CornerMode.Profile) nav.navigate(Saved) },
                                onChoose = { chosen, place, finger -> go(chosen.site, place, finger) },
                                enabled = { currentMode == CornerMode.Profile },
                            )
                        }
                        .semantics {
                            role = Role.Button
                            contentDescription = if (mode == CornerMode.Back) "Back" else "Profile and saved stories"
                            onClick(label = if (mode == CornerMode.Back) "Back" else "Profile and saved stories") {
                                if (mode == CornerMode.Back) nav.popBackStack() else nav.navigate(Saved)
                                true
                            }
                            if (mode == CornerMode.Profile) {
                                val (home, other) = reelSites()
                                val center = reel.button.center - reel.origin
                                customActions = home.places.map { place ->
                                    CustomAccessibilityAction(place.title) { go(home.site, place, center); true }
                                } + CustomAccessibilityAction("Switch to ${other.site.title}") {
                                    go(other.site, Place.of(feedOf(other.site)), center); true
                                }
                            }
                        },
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Crossfade(mode == CornerMode.Back, label = "corner icon") { back ->
                            Icon(if (back) HnIcons.back else HnIcons.person, contentDescription = null, modifier = Modifier.size(24.dp))
                        }
                    }
                }
            }
        }
    }
}

/** A site switch under way: the old screen, and where the new one floods out from. */
private class Flood(val image: ImageBitmap, val center: Offset, val circle: Boolean)
