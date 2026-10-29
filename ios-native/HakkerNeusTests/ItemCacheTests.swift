import Testing
@testable import HakkerNeus

struct ItemCacheTests {
    private let item = StoryWithComments(story: .stub(id: 1), comments: [.stub(2)])

    @Test func cachesAndSharesRequests() async throws {
        let client = StubClient(ids: [])
        await client.setItem(item, id: 1)
        let cache = ItemCache(client: client)

        async let a = cache.item(id: 1)
        async let b = cache.item(id: 1)
        _ = try await (a, b)
        #expect(try await cache.item(id: 1) == item)

        #expect(await client.itemRequests == [1])
    }

    @Test func forceRefreshRefetches() async throws {
        let client = StubClient(ids: [])
        await client.setItem(item, id: 1)
        let cache = ItemCache(client: client)

        _ = try await cache.item(id: 1)
        _ = try await cache.item(id: 1, forceRefresh: true)

        #expect(await client.itemRequests == [1, 1])
    }

    @Test func failuresAreNotCached() async throws {
        let client = StubClient(ids: [])
        await client.setItem(item, id: 1)
        await client.setFailing(1, true)
        let cache = ItemCache(client: client)

        await #expect(throws: HNClientError.badStatus(500)) { try await cache.item(id: 1) }

        await client.setFailing(1, false)
        #expect(try await cache.item(id: 1) == item)
    }
}
