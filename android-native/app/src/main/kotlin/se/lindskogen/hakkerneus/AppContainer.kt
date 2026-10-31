package se.lindskogen.hakkerneus

import android.content.Context
import androidx.compose.runtime.setValue
import androidx.compose.runtime.getValue
import android.widget.Toast
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import se.lindskogen.hakkerneus.account.HnSession
import se.lindskogen.hakkerneus.data.Comment
import se.lindskogen.hakkerneus.data.HnClient
import se.lindskogen.hakkerneus.data.LiveHnClient
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.persistence.Database
import se.lindskogen.hakkerneus.persistence.OfflineItemStore
import se.lindskogen.hakkerneus.persistence.SavedStoriesStore
import se.lindskogen.hakkerneus.persistence.VisitedStoriesStore
import se.lindskogen.hakkerneus.ui.comments.CommentTextStyle
import se.lindskogen.hakkerneus.ui.theme.ColorTheme
import se.lindskogen.hakkerneus.ui.theme.Palette

/** App-wide dependencies (the Android counterpart of the iOS AppCoordinator's properties). */
object AppContainer {
    val client: HnClient = LiveHnClient()
    val users = se.lindskogen.hakkerneus.data.UserCache(se.lindskogen.hakkerneus.data.UserApi())
    val items = se.lindskogen.hakkerneus.data.ItemCache(client)

    /**
     * Starts fetching a story's comments as soon as the user shows interest (touching the row,
     * starting a swipe, opening its menu), so the comments screen usually opens already loaded.
     */
    fun prefetchComments(id: Long) = items.prefetch(id)

    /** Fetches the profile and first stories of a user whose page is one tap away. */
    fun prefetchUser(name: String) = users.prefetch(name)

    /** On unmetered networks (not cellular, not Data Saver), fetches the comments of the rows on screen. */
    fun prefetchVisible(stories: List<Story>) {
        val connectivity = appContext.getSystemService(android.net.ConnectivityManager::class.java) ?: return
        if (connectivity.isActiveNetworkMetered) return
        stories.take(10).filter { it.commentCount > 0 }.forEach { items.prefetch(it.id) }
    }

    /** Stories seen in a list, so the comments screen can show the header before loading. */
    val knownStories = mutableMapOf<Long, Story>()

    lateinit var appContext: Context
        private set
    lateinit var saved: SavedStoriesStore
        private set
    lateinit var visited: VisitedStoriesStore
        private set
    lateinit var offline: OfflineItemStore
        private set
    lateinit var session: HnSession
        private set
    lateinit var hidden: se.lindskogen.hakkerneus.persistence.HiddenStoriesStore
        private set

    /** Unsent comment drafts, by the ID of what they reply to. */
    val drafts = mutableMapOf<Long, String>()

    /** A comment posted from the app, shown until Algolia has it. */
    data class LocalReply(val storyId: Long, val parentId: Long, val comment: Comment)
    val localReplies = MutableStateFlow<List<LocalReply>>(emptyList())

    /** What to do once signing in succeeds (e.g. the vote that asked for it). */
    var afterSignIn: (() -> Unit)? = null

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    /**
     * Upvotes the story or undoes it: the UI updates straight away and rolls back if HN
     * refuses. Signed out (or expired), asks to sign in first and then votes.
     */
    fun toggleVote(story: Story, requireSignIn: () -> Unit) {
        if (!session.isSignedIn) {
            afterSignIn = { toggleVote(story, requireSignIn) }
            requireSignIn()
            return
        }
        val was = story.id in session.upvoted.value
        session.setLocalVote(story.id, !was)
        scope.launch {
            try {
                session.vote(story.id, !was)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                session.setLocalVote(story.id, was, counted = true)
                if (e is HnSession.Failure.SessionExpired) {
                    session.signOut()
                    afterSignIn = { toggleVote(story, requireSignIn) }
                    requireSignIn()
                } else {
                    Toast.makeText(appContext, e.message ?: "The vote didn't go through.", Toast.LENGTH_LONG).show()
                }
            }
        }
    }

    private val settings get() = appContext.getSharedPreferences("settings", Context.MODE_PRIVATE)

    /** Picks the front page's colours, and remembers the choice. */
    fun setColorTheme(theme: ColorTheme) {
        Palette.theme = theme
        settings.edit().putString("colorTheme", theme.name).apply()
        useLauncherIcon(theme)
    }

    /** Shows the launcher entry (activity-alias) with [theme]'s icon and hides the others. */
    private fun useLauncherIcon(theme: ColorTheme) {
        val packageManager = appContext.packageManager
        for (each in ColorTheme.entries) {
            val component = android.content.ComponentName(appContext, "se.lindskogen.hakkerneus.Launcher${each.name}")
            val state = if (each == theme) android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else android.content.pm.PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            if (packageManager.getComponentEnabledSetting(component) != state) {
                packageManager.setComponentEnabledSetting(component, state, android.content.pm.PackageManager.DONT_KILL_APP)
            }
        }
    }

    /** The corner button sits lower-left (for left hands) instead of lower-right. Compose state. */
    var cornerButtonOnLeft by androidx.compose.runtime.mutableStateOf(false)
        private set

    fun placeCornerButton(onLeft: Boolean) {
        cornerButtonOnLeft = onLeft
        settings.edit().putBoolean("cornerButtonOnLeft", onLeft).apply()
    }

    /** The choices for [newMinimumScore]; 0 shows everything. */
    val newMinimumScoreOptions = listOf(0, 2, 5, 10, 25)

    /** The New list only shows stories with at least this many points. Compose state. */
    var newMinimumScore by androidx.compose.runtime.mutableStateOf(0)
        private set

    fun updateNewMinimumScore(score: Int) {
        newMinimumScore = score
        settings.edit().putInt("newMinimumScore", score).apply()
    }

    /** Code block wrapping and size, remembered. */
    fun setCommentTextStyle(wrapsLines: Boolean = CommentTextStyle.wrapsLines, size: CommentTextStyle.Size = CommentTextStyle.size) {
        CommentTextStyle.wrapsLines = wrapsLines
        CommentTextStyle.size = size
        settings.edit().putBoolean("codeWrapsLines", wrapsLines).putString("codeSize", size.name).apply()
    }

    fun init(context: Context) {
        if (::saved.isInitialized) return
        appContext = context.applicationContext
        val db = Database(appContext)
        saved = SavedStoriesStore(db)
        visited = VisitedStoriesStore(db)
        offline = OfflineItemStore(db)
        session = HnSession(appContext)
        hidden = se.lindskogen.hakkerneus.persistence.HiddenStoriesStore(appContext)
        cornerButtonOnLeft = settings.getBoolean("cornerButtonOnLeft", false)
        newMinimumScore = settings.getInt("newMinimumScore", 0)
        CommentTextStyle.wrapsLines = settings.getBoolean("codeWrapsLines", false)
        CommentTextStyle.size = settings.getString("codeSize", null)?.let { name -> CommentTextStyle.Size.entries.find { it.name == name } } ?: CommentTextStyle.Size.Medium
        Palette.theme = settings.getString("colorTheme", null)?.let { name -> ColorTheme.entries.find { it.name == name } } ?: ColorTheme.Orange
        // Themes picked before icons followed them (Android shows no prompt, so just fix it).
        useLauncherIcon(Palette.theme)
    }
}
