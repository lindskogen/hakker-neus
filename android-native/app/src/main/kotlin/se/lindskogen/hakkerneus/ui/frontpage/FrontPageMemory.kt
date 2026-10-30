package se.lindskogen.hakkerneus.ui.frontpage

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import se.lindskogen.hakkerneus.AppContainer
import se.lindskogen.hakkerneus.data.TopStoriesFeed

/** The loaded front page and its scroll position, kept between launches (like the iOS app). */
object FrontPageMemory {
    @Serializable
    data class Saved(val snapshot: TopStoriesFeed.Snapshot, val anchorId: Long?, val anchorOffset: Int)

    private val json = Json { ignoreUnknownKeys = true }
    private val prefs get() = AppContainer.appContext.getSharedPreferences("restoration", Context.MODE_PRIVATE)

    fun load(): Saved? = prefs.getString("frontPage", null)?.let { runCatching { json.decodeFromString(Saved.serializer(), it) }.getOrNull() }

    fun save(saved: Saved) = prefs.edit().putString("frontPage", json.encodeToString(Saved.serializer(), saved)).apply()
}
