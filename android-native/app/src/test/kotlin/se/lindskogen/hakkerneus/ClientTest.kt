package se.lindskogen.hakkerneus

import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import se.lindskogen.hakkerneus.data.AlgoliaApi
import se.lindskogen.hakkerneus.data.FirebaseApi
import se.lindskogen.hakkerneus.data.HnClient
import se.lindskogen.hakkerneus.data.HttpException
import se.lindskogen.hakkerneus.data.HttpTransport
import se.lindskogen.hakkerneus.data.Story
import se.lindskogen.hakkerneus.data.StoryWithComments
import se.lindskogen.hakkerneus.data.TopStoriesFeed
import se.lindskogen.hakkerneus.data.flattened

private class StubTransport(val responses: Map<String, String>) : HttpTransport {
    override suspend fun get(url: String) = responses.entries.firstOrNull { url.endsWith(it.key) }?.value ?: throw HttpException(404)
}

class ClientTest {
    @Test
    fun decodesFirebaseStoriesAndSkipsDeadOnes() = runTest {
        val api = FirebaseApi(StubTransport(mapOf(
            "item/1.json" to """{"by":"pg","descendants":3,"id":1,"score":57,"time":1160418111,"title":"Y Combinator","type":"story","url":"http://ycombinator.com"}""",
            "item/9.json" to """{"dead":true,"id":9,"by":"x","time":1,"title":"Spam"}""",
            "item/10.json" to "null",
        )))
        assertEquals(Story(1, "Y Combinator", "pg", "http://ycombinator.com", null, 57, 3, 1160418111), api.story(1))
        assertNull(api.story(9))
        assertNull(api.story(10))
    }

    @Test
    fun decodesRecordedAlgoliaItem() = runTest {
        val json = javaClass.classLoader!!.getResource("algolia-item-1.json")!!.readText()
        val item = AlgoliaApi(StubTransport(mapOf("items/1" to json))).item(1)
        assertEquals("Y Combinator", item.story.title)
        assertEquals(3, item.story.commentCount)
        assertEquals(listOf(15L, 17, 1079), item.comments.flattened().map { it.id })
        assertNull(item.parentStoryId)
    }

    @Test
    fun algoliaCommentsKnowTheirStory() = runTest {
        val json = """{"id":17,"type":"comment","story_id":1,"author":"pg","text":"hi","created_at_i":0,"children":[]}"""
        assertEquals(1L, AlgoliaApi(StubTransport(mapOf("items/17" to json))).item(17).parentStoryId)
    }
}

private class StubClient(var ids: List<Long>) : HnClient {
    var idRequests = 0
    override suspend fun topStoryIds(): List<Long> { idRequests++; return ids }
    override suspend fun story(id: Long) = if (id < 0) null else Story(id, "Story $id")
    override suspend fun item(id: Long): StoryWithComments = throw UnsupportedOperationException()
}

class TopStoriesFeedTest {
    @Test
    fun pagesInRankOrderDroppingMissingAndDuplicates() = runTest {
        val feed = TopStoriesFeed(StubClient(listOf(5, 3, -1, 3, 9)), pageSize = 2)
        assertEquals(listOf(5L, 3), feed.reload().map { it.id })
        assertEquals(listOf(5L, 3), feed.loadNextPage().map { it.id })
        assertEquals(listOf(5L, 3, 9), feed.loadNextPage().map { it.id })
    }

    @Test
    fun restoresASnapshotAndKeepsTheSavedRanking() = runTest {
        val client = StubClient(listOf(5, 3, 9, 1))
        val original = TopStoriesFeed(client, pageSize = 2)
        original.reload()
        client.ids = listOf(1, 9, 3, 5)
        val restored = TopStoriesFeed(client, pageSize = 2).apply { restore(original.snapshot!!) }
        assertEquals(listOf(5L, 3, 9, 1), restored.loadNextPage().map { it.id })
        assertEquals(1, client.idRequests)
    }
}
