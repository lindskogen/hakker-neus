import Foundation

/// Requests keyed by what they fetch, so a screen can be fetched before it's pushed (on touch
/// down, when a swipe starts, when a menu opens) and the screen picks up the same request.
/// Concurrent requests for the same key share one fetch; results go stale after `maxAge`, and
/// only the most recent `limit` are kept.
actor RequestCache<Key: Hashable & Sendable, Value: Sendable> {
    private struct Entry {
        let task: Task<Value, Error>
        let started: Date
    }

    private let maxAge: TimeInterval
    private let limit: Int
    private var entries: [Key: Entry] = [:]

    init(maxAge: TimeInterval = 5 * 60, limit: Int = 60) {
        self.maxAge = maxAge
        self.limit = limit
    }

    func value(for key: Key, forceRefresh: Bool = false, fetch: @escaping @Sendable () async throws -> Value) async throws -> Value {
        if !forceRefresh, let existing = entries[key], -existing.started.timeIntervalSinceNow < maxAge {
            return try await existing.task.value
        }

        // Detached: parsing in `fetch` mustn't hold up other lookups on this actor.
        let task = Task.detached { try await fetch() }
        entries[key] = Entry(task: task, started: Date())
        if entries.count > limit, let oldest = entries.min(by: { $0.value.started < $1.value.started })?.key {
            entries[oldest] = nil
        }
        do {
            return try await task.value
        } catch {
            // Don't keep failures around; the next request should retry.
            if entries[key]?.task == task { entries[key] = nil }
            throw error
        }
    }
}

/// An item with its comments' HTML already parsed, by comment ID.
struct LoadedItem: Sendable {
    let item: StoryWithComments
    let bodies: [Int: CommentBody]
}

/// Comment trees by item ID, parsed as part of the fetch so a prefetched thread is ready to show.
struct ItemCache: Sendable {
    private let client: HNClient
    private let cache = RequestCache<Int, LoadedItem>()

    init(client: HNClient) {
        self.client = client
    }

    func item(id: Int, forceRefresh: Bool = false) async throws -> LoadedItem {
        try await cache.value(for: id, forceRefresh: forceRefresh) { [client] in
            let item = try await client.item(id: id)
            let bodies = Dictionary(
                item.comments.flattened().map { ($0.id, CommentBody(html: $0.comment.text ?? "")) },
                uniquingKeysWith: { $1 }
            )
            return LoadedItem(item: item, bodies: bodies)
        }
    }

    func prefetch(id: Int) {
        Task { _ = try? await item(id: id) }
    }
}
