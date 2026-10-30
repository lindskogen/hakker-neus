package se.lindskogen.hakkerneus

import android.content.Context
import se.lindskogen.hakkerneus.data.HnClient
import se.lindskogen.hakkerneus.data.LiveHnClient
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.persistence.Database
import se.lindskogen.hakkerneus.persistence.OfflineItemStore
import se.lindskogen.hakkerneus.persistence.SavedStoriesStore
import se.lindskogen.hakkerneus.persistence.VisitedStoriesStore

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

    fun init(context: Context) {
        if (::saved.isInitialized) return
        appContext = context.applicationContext
        val db = Database(appContext)
        saved = SavedStoriesStore(db)
        visited = VisitedStoriesStore(db)
        offline = OfflineItemStore(db)
    }
}
