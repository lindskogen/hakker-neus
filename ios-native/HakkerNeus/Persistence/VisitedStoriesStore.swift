import Foundation

/// Which stories the user has opened, and how many comments they had when the comments were
/// last opened, so the lists can dim read stories and show how many comments are new.
@MainActor
final class VisitedStoriesStore {
    /// Posted after a visit is recorded. `object` is the story ID as an `Int`.
    static let didChange = Notification.Name("VisitedStoriesStore.didChange")

    struct Visit: Equatable {
        var openedAt: Date
        /// Nil until the comments have been opened.
        var seenCommentCount: Int?
    }

    private let database: Database
    private var visits: [Int: Visit] = [:]
    /// Called with the story ID after a visit on this device (not one from iCloud).
    var onChange: ((Int) -> Void)?

    init(database: Database) throws {
        self.database = database
        try Schema.migrate(database)
        for row in try database.query("SELECT id, opened_at, seen_comment_count FROM visited_stories") {
            guard let id = row.int(0), let openedAt = row.double(1) else { continue }
            visits[id] = Visit(openedAt: Date(timeIntervalSince1970: openedAt), seenCommentCount: row.int(2))
        }
    }

    func isVisited(_ id: Int) -> Bool {
        visits[id] != nil
    }

    func visit(_ id: Int) -> Visit? {
        visits[id]
    }

    var allIDs: [Int] { Array(visits.keys) }

    /// Comments added since the comments were last opened; nil if never opened or none are new.
    func newCommentCount(for story: Story) -> Int? {
        guard let seen = visits[story.id]?.seenCommentCount, story.commentCount > seen else { return nil }
        return story.commentCount - seen
    }

    /// The story's link was opened.
    func markOpened(_ story: Story, at date: Date = Date()) {
        record(story.id, Visit(openedAt: date, seenCommentCount: visits[story.id]?.seenCommentCount))
    }

    /// The story's comments were opened; its current comment count counts as read.
    func markCommentsSeen(_ story: Story, at date: Date = Date()) {
        record(story.id, Visit(openedAt: date, seenCommentCount: story.commentCount))
    }

    /// Visits from another device, through iCloud, merged with this device's: the later opening
    /// and the higher seen comment count win.
    func applyRemote(_ remote: [Int: Visit]) throws {
        var changed: [Int: Visit] = [:]
        for (id, visit) in remote {
            var merged = visits[id] ?? visit
            merged.openedAt = max(merged.openedAt, visit.openedAt)
            if let seen = visit.seenCommentCount { merged.seenCommentCount = max(merged.seenCommentCount ?? seen, seen) }
            if merged != visits[id] { changed[id] = merged }
        }
        guard !changed.isEmpty else { return }
        try database.transaction {
            for (id, visit) in changed { try insert(id, visit) }
        }
        visits.merge(changed) { $1 }
        NotificationCenter.default.post(name: Self.didChange, object: changed.count == 1 ? changed.first?.key : nil)
    }

    private func record(_ id: Int, _ visit: Visit) {
        do {
            try insert(id, visit)
            visits[id] = visit
            NotificationCenter.default.post(name: Self.didChange, object: id)
            onChange?(id)
        } catch {
            assertionFailure("Couldn't record visit to \(id): \(error)")
        }
    }

    private func insert(_ id: Int, _ visit: Visit) throws {
        try database.run(
            "INSERT OR REPLACE INTO visited_stories (id, opened_at, seen_comment_count) VALUES (?, ?, ?)",
            [.init(id), .init(visit.openedAt), visit.seenCommentCount.map { .init($0) } ?? .null]
        )
    }
}
