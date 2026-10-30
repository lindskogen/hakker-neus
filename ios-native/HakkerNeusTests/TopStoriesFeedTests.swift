import Testing
@testable import HakkerNeus

@MainActor
struct TopStoriesFeedTests {
    @Test func loadsPagesInRankOrder() async throws {
        let client = StubClient.withStories([5, 3, 9, 1, 7])
        let feed = TopStoriesFeed(client: client, pageSize: 2)

        #expect(try await feed.reload().map(\.id) == [5, 3])
        #expect(feed.hasMore)
        #expect(try await feed.loadNextPage().map(\.id) == [5, 3, 9, 1])
        #expect(try await feed.loadNextPage().map(\.id) == [5, 3, 9, 1, 7])
        #expect(!feed.hasMore)

        // Nothing left to fetch.
        #expect(try await feed.loadNextPage().count == 5)
        #expect(await client.storyRequests.count == 5)
    }

    @Test func dropsMissingStoriesAndDuplicates() async throws {
        let client = StubClient(ids: [1, 2, 1, 3], stories: [1: .stub(id: 1), 3: .stub(id: 3)])
        let feed = TopStoriesFeed(client: client, pageSize: 10)

        #expect(try await feed.reload().map(\.id) == [1, 3])
    }

    @Test func reloadStartsOverWithNewRanking() async throws {
        let client = StubClient.withStories([1, 2, 3, 4])
        let feed = TopStoriesFeed(client: client, pageSize: 2)
        try await feed.reload()
        try await feed.loadNextPage()

        await client.setIDs([4, 3, 2, 1])

        #expect(try await feed.reload().map(\.id) == [4, 3])
        #expect(await client.idRequests == 2)
    }

    @Test func restoresASnapshotAndKeepsPagingTheSameRanking() async throws {
        let client = StubClient.withStories([5, 3, 9, 1, 7])
        let original = TopStoriesFeed(client: client, pageSize: 2)
        try await original.reload()
        let snapshot = try #require(original.snapshot)

        // The live ranking has moved on since; the restored feed keeps the saved one.
        await client.setIDs([7, 1, 9, 3, 5])
        let restored = TopStoriesFeed(client: client, pageSize: 2)
        restored.restore(snapshot)

        #expect(restored.stories.map(\.id) == [5, 3])
        #expect(try await restored.loadNextPage().map(\.id) == [5, 3, 9, 1])
        #expect(await client.idRequests == 1)
    }

    @Test func nothingToSnapshotBeforeLoading() {
        #expect(TopStoriesFeed(client: StubClient(ids: [])).snapshot == nil)
    }

    @Test func concurrentLoadsShareOneRequest() async throws {
        let client = StubClient.withStories(Array(1...6))
        let feed = TopStoriesFeed(client: client, pageSize: 2)
        try await feed.reload()

        async let first = feed.loadNextPage()
        async let second = feed.loadNextPage()
        let (a, b) = try await (first, second)

        #expect(a.map(\.id) == [1, 2, 3, 4])
        #expect(b.map(\.id) == [1, 2, 3, 4])
        #expect(await client.storyRequests.count == 4)
    }
}
