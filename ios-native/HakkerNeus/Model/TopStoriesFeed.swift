import Foundation

/// Paginated front page, replacing `useNewsList` in `fetchNewsList.ts`.
///
/// `reload()` takes a snapshot of the ranked IDs and `loadNextPage()` fetches the stories for the
/// next slice of that snapshot in parallel. Pull-to-refresh calls `reload()` to get a new ranking.
@MainActor
final class TopStoriesFeed {
    static let pageSize = 40

    private let client: HNClient
    private let pageSize: Int

    private var ids: [Int] = []
    private var nextOffset = 0
    private var generation = 0
    private var pageTask: Task<Void, Error>?

    private(set) var stories: [Story] = []
    var hasMore: Bool { nextOffset < ids.count }

    /// Everything needed to show the same list again after a relaunch.
    struct Snapshot: Codable, Equatable {
        var ids: [Int]
        var nextOffset: Int
        var stories: [Story]
    }

    /// Nil until something has loaded.
    var snapshot: Snapshot? {
        stories.isEmpty ? nil : Snapshot(ids: ids, nextOffset: nextOffset, stories: stories)
    }

    /// Shows a saved list again; paging continues from the same ranking.
    func restore(_ snapshot: Snapshot) {
        generation += 1
        pageTask?.cancel()
        pageTask = nil
        ids = snapshot.ids
        nextOffset = min(snapshot.nextOffset, snapshot.ids.count)
        stories = snapshot.stories
    }

    init(client: HNClient, pageSize: Int = TopStoriesFeed.pageSize) {
        self.client = client
        self.pageSize = pageSize
    }

    /// Fetches a new ranking and its first page. Returns all loaded stories.
    @discardableResult
    func reload() async throws -> [Story] {
        generation += 1
        pageTask?.cancel()
        pageTask = nil

        let generation = generation
        let ids = try await client.topStoryIDs()
        guard generation == self.generation else { throw CancellationError() }

        self.ids = ids
        nextOffset = 0
        stories = []
        return try await loadNextPage()
    }

    /// Appends the next page. Concurrent calls share one request. Returns all loaded stories.
    @discardableResult
    func loadNextPage() async throws -> [Story] {
        if pageTask == nil {
            guard hasMore else { return stories }
            pageTask = makePageTask()
        }
        try await pageTask?.value
        return stories
    }

    /// Fetches the next slice and appends it, so every caller awaiting it sees the result.
    private func makePageTask() -> Task<Void, Error> {
        let generation = generation
        let slice = Array(ids[nextOffset..<min(nextOffset + pageSize, ids.count)])

        return Task { [client] in
            defer { if generation == self.generation { pageTask = nil } }

            let page = try await Self.fetch(slice, client: client)
            guard generation == self.generation else { throw CancellationError() }

            nextOffset += slice.count
            var known = Set(stories.map(\.id))
            stories += page.filter { known.insert($0.id).inserted }
        }
    }

    /// Fetches stories concurrently, keeping the input order and dropping missing ones.
    private nonisolated static func fetch(_ ids: [Int], client: HNClient) async throws -> [Story] {
        try await withThrowingTaskGroup(of: (Int, Story?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await client.story(id: id)) }
            }
            var results = [Story?](repeating: nil, count: ids.count)
            for try await (index, story) in group {
                results[index] = story
            }
            return results.compactMap { $0 }
        }
    }
}
