package se.lindskogen.hakkerneus.data

import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable

/**
 * Paginated front page (or HN's New list, with [Source.New]). [reload] takes a snapshot of the ranked IDs and [loadNextPage] fetches
 * the next slice of that snapshot in parallel. Concurrent page loads share one request.
 */
class TopStoriesFeed(private val client: HnClient, val source: Source = Source.Top, private val pageSize: Int = PAGE_SIZE) {
    /** Which HN list: the ranked front page or the newest stories. */
    enum class Source { Top, New }

    companion object {
        const val PAGE_SIZE = 40
    }

    /** Everything needed to show the same list again after a relaunch. */
    @Serializable
    data class Snapshot(val ids: List<Long>, val nextOffset: Int, val stories: List<Story>)

    private val mutex = Mutex()
    private var ids: List<Long> = emptyList()
    private var nextOffset = 0

    var stories: List<Story> = emptyList()
        private set

    val hasMore: Boolean get() = nextOffset < ids.size

    val snapshot: Snapshot? get() = if (stories.isEmpty()) null else Snapshot(ids, nextOffset, stories)

    fun restore(snapshot: Snapshot) {
        ids = snapshot.ids
        nextOffset = snapshot.nextOffset.coerceAtMost(snapshot.ids.size)
        stories = snapshot.stories
    }

    /** Fetches a new ranking and its first page. Returns all loaded stories. */
    suspend fun reload(): List<Story> {
        val fresh = if (source == Source.Top) client.topStoryIds() else client.newStoryIds()
        mutex.withLock {
            ids = fresh
            nextOffset = 0
            stories = emptyList()
        }
        return loadNextPage()
    }

    /** Appends the next page (if any). Returns all loaded stories. */
    suspend fun loadNextPage(): List<Story> = mutex.withLock {
        if (!hasMore) return stories
        val slice = ids.subList(nextOffset, minOf(nextOffset + pageSize, ids.size))
        val page = client.stories(slice)
        nextOffset += slice.size
        val known = stories.mapTo(HashSet()) { it.id }
        stories = stories + page.filter { known.add(it.id) }
        stories
    }
}
