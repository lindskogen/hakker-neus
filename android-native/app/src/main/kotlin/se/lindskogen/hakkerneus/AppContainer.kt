package se.lindskogen.hakkerneus

import android.content.Context
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
import se.lindskogen.hakkerneus.ui.theme.ColorTheme
import se.lindskogen.hakkerneus.ui.theme.Palette

/** App-wide dependencies (the Android counterpart of the iOS AppCoordinator's properties). */
object AppContainer {
    val client: HnClient = LiveHnClient()

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
    }

    fun init(context: Context) {
        if (::saved.isInitialized) return
        appContext = context.applicationContext
        val db = Database(appContext)
        saved = SavedStoriesStore(db)
        visited = VisitedStoriesStore(db)
        offline = OfflineItemStore(db)
        session = HnSession(appContext)
        Palette.theme = settings.getString("colorTheme", null)?.let { name -> ColorTheme.entries.find { it.name == name } } ?: ColorTheme.Orange
    }
}
