import Foundation

/// In-memory cache of comment trees, so tapping a story can start the request before
/// the comments screen is pushed. Concurrent requests for the same ID share one fetch.
actor ItemCache {
    private let client: HNClient
    private var entries: [Int: Task<StoryWithComments, Error>] = [:]

    init(client: HNClient) {
        self.client = client
    }

    func item(id: Int, forceRefresh: Bool = false) async throws -> StoryWithComments {
        if !forceRefresh, let existing = entries[id] {
            return try await existing.value
        }

        let task = Task { [client] in try await client.item(id: id) }
        entries[id] = task
        do {
            return try await task.value
        } catch {
            // Don't keep failures around; the next request should retry.
            if entries[id] == task { entries[id] = nil }
            throw error
        }
    }

    nonisolated func prefetch(id: Int) {
        Task { _ = try? await item(id: id) }
    }
}
