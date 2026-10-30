package se.lindskogen.hakkerneus

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import se.lindskogen.hakkerneus.data.HnClient
import se.lindskogen.hakkerneus.data.LiveHnClient
import se.lindskogen.hakkerneus.data.Story

/** App-wide dependencies (the Android counterpart of the iOS AppCoordinator's properties). */
object AppContainer {
    val client: HnClient = LiveHnClient()

    /** Stories seen in a list, so the comments screen can show the header before loading. */
    val knownStories = mutableMapOf<Long, Story>()

    // In memory until the database lands in A4.
    private val savedIds = MutableStateFlow<Set<Long>>(emptySet())
    val saved: StateFlow<Set<Long>> = savedIds

    fun toggleSaved(story: Story) {
        savedIds.value = if (story.id in savedIds.value) savedIds.value - story.id else savedIds.value + story.id
    }
}
