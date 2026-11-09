package se.lindskogen.hakkerneus

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Test
import se.lindskogen.hakkerneus.data.HttpException
import se.lindskogen.hakkerneus.data.HttpTransport
import se.lindskogen.hakkerneus.data.Lobsters
import se.lindskogen.hakkerneus.data.LobstersApi
import se.lindskogen.hakkerneus.data.SourceRoutingClient
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.StoryWithComments
import se.lindskogen.hakkerneus.data.HnClient

class LobstersTest {
    private class Transport(val responses: Map<String, String>) : HttpTransport {
        val requested = mutableListOf<String>()
        override suspend fun get(url: String): String {
            requested += url
            return responses[url] ?: throw HttpException(404)
        }
    }

    private fun page(vararg shortIds: String) = shortIds.joinToString(",", "[", "]") {
        """{"short_id":"$it","created_at":"2026-11-09T10:00:00.000-06:00","title":"Story $it","url":"https://example.com/$it","score":3,"comment_count":1,"submitter_user":"someone"}"""
    }

    private object NoHn : HnClient {
        override suspend fun topStoryIds() = emptyList<Long>()
        override suspend fun newStoryIds() = emptyList<Long>()
        override suspend fun story(id: Long): Story? = null
        override suspend fun item(id: Long): StoryWithComments = throw UnsupportedOperationException()
    }

    @Test
    fun readsNewestFromItsOwnPages() = runTest {
        val transport = Transport(mapOf(
            "https://lobste.rs/newest.json" to page("aaaaaa", "bbbbbb"),
            "https://lobste.rs/newest/page/2.json" to page("cccccc"),
            "https://lobste.rs/newest/page/3.json" to page(),
            "https://lobste.rs/newest/page/4.json" to page(),
        ))
        val client = SourceRoutingClient(NoHn, LobstersApi(transport))
        val ids = client.lobstersNewestIds()
        assertEquals(listOf("aaaaaa", "bbbbbb", "cccccc").map { Lobsters.id(it) }, ids)
        // The stories come from the list, without a request each.
        assertEquals("Story cccccc", client.story(Lobsters.id("cccccc")!!)?.title)
        assertEquals(4, transport.requested.size)
    }

    @Test
    fun readsHottestFromTheFrontPages() = runTest {
        val transport = Transport(mapOf(
            "https://lobste.rs/hottest.json" to page("aaaaaa"),
            "https://lobste.rs/page/2.json" to page("bbbbbb"),
            "https://lobste.rs/page/3.json" to page(),
            "https://lobste.rs/page/4.json" to page(),
        ))
        assertEquals(listOf("aaaaaa", "bbbbbb").map { Lobsters.id(it) }, SourceRoutingClient(NoHn, LobstersApi(transport)).lobstersHottestIds())
    }
}
