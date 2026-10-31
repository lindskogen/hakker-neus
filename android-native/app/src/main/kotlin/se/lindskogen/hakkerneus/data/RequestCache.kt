package se.lindskogen.hakkerneus.data

import android.os.SystemClock
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import se.lindskogen.hakkerneus.html.CommentBody

/**
 * Requests keyed by what they fetch, so a screen can be fetched before it's opened (on touch
 * down, when a swipe starts, when a menu opens) and the screen picks up the same request.
 * Concurrent requests for the same key share one fetch; results go stale after [maxAgeMs], and
 * only the most recent [limit] are kept.
 */
class RequestCache<K : Any, V>(private val maxAgeMs: Long = 5 * 60_000L, private val limit: Int = 60) {
    private class Entry<V>(val deferred: Deferred<V>, val started: Long)

    private val mutex = Mutex()
    private val entries = HashMap<K, Entry<V>>()
    // Not tied to a screen: a prefetch keeps going if the user backs out, ready for next time.
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    suspend fun get(key: K, forceRefresh: Boolean = false, fetch: suspend () -> V): V {
        val entry = mutex.withLock {
            val existing = entries[key]
            if (!forceRefresh && existing != null && SystemClock.elapsedRealtime() - existing.started < maxAgeMs) {
                existing
            } else {
                Entry(scope.async { fetch() }, SystemClock.elapsedRealtime()).also {
                    entries[key] = it
                    if (entries.size > limit) entries.minByOrNull { e -> e.value.started }?.let { e -> entries.remove(e.key) }
                }
            }
        }
        return try {
            entry.deferred.await()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Don't keep failures around; the next request should retry.
            mutex.withLock { if (entries[key] === entry) entries.remove(key) }
            throw e
        }
    }

    fun prefetch(key: K, fetch: suspend () -> V) {
        scope.launch { runCatching { get(key, fetch = fetch) } }
    }
}

/** An item with its comments' HTML already parsed, by comment ID. */
class LoadedItem(val item: StoryWithComments, val bodies: Map<Long, CommentBody>)

/** Comment trees by item ID, parsed as part of the fetch so a prefetched thread is ready to show. */
class ItemCache(private val client: HnClient) {
    private val cache = RequestCache<Long, LoadedItem>()

    suspend fun item(id: Long, forceRefresh: Boolean = false): LoadedItem = cache.get(id, forceRefresh) { load(id) }

    fun prefetch(id: Long) = cache.prefetch(id) { load(id) }

    private suspend fun load(id: Long): LoadedItem {
        val item = client.item(id)
        val bodies = item.comments.flattened().associate { it.id to CommentBody.parse(it.comment.text ?: "") }
        return LoadedItem(item, bodies)
    }
}

/**
 * User pages' profiles and first pages of stories, so a user page can be fetched as soon as a
 * menu offering it opens. Later pages and comments go straight to the API.
 */
class UserCache(val api: UserApi) {
    private val users = RequestCache<String, HnUser>(limit = 30)
    private val firstStories = RequestCache<String, UserActivityPage<Story>>(limit = 30)

    suspend fun user(name: String): HnUser = users.get(name) { api.user(name) }

    suspend fun stories(name: String, page: Int): UserActivityPage<Story> =
        if (page == 0) firstStories.get(name) { api.stories(name, 0) } else api.stories(name, page)

    suspend fun comments(name: String, page: Int) = api.comments(name, page)

    fun prefetch(name: String) {
        users.prefetch(name) { api.user(name) }
        firstStories.prefetch(name) { api.stories(name, 0) }
    }
}
