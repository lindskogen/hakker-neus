import Foundation

/// A comment the user saved, with the story it's on, kept whole so the list works offline.
struct SavedComment: Hashable, Sendable, Identifiable {
    let id: Int
    let author: String?
    /// HN's HTML.
    let text: String
    let time: Date
    let storyID: Int?
    let storyTitle: String?
    let savedAt: Date

    var hackerNewsURL: URL { Lobsters.isLobsters(id) ? Lobsters.commentURL(id) : .hackerNewsItem(id) }
}

/// Comments the user has saved, newest first, kept in the app's SQLite database next to the
/// saved stories. Reads come from an in-memory copy loaded at startup.
@MainActor
final class SavedCommentsStore {
    /// Posted after a comment is saved or removed. `object` is the comment ID as an `Int`.
    static let didChange = Notification.Name("SavedCommentsStore.didChange")

    private let database: Database
    private var entries: [Int: SavedComment] = [:]
    /// Called with the comment ID after a change made on this device (not one from iCloud).
    var onChange: ((Int) -> Void)?

    init(database: Database) throws {
        self.database = database
        try Schema.migrate(database)
        entries = try loadEntries()
    }

    /// Most recently saved first.
    var all: [SavedComment] {
        entries.values.sorted { $0.savedAt > $1.savedAt }
    }

    func isSaved(_ id: Int) -> Bool {
        entries[id] != nil
    }

    func entry(_ id: Int) -> SavedComment? {
        entries[id]
    }

    /// Saves `comment`, on the story with `storyID` and `storyTitle` if known.
    func save(_ comment: Comment, storyID: Int?, storyTitle: String?) {
        guard let text = comment.text else { return }
        let entry = SavedComment(
            id: comment.id, author: comment.author, text: text, time: comment.time,
            storyID: storyID, storyTitle: storyTitle, savedAt: Date()
        )
        do {
            try insert(entry)
            entries[entry.id] = entry
            NotificationCenter.default.post(name: Self.didChange, object: entry.id)
            onChange?(entry.id)
        } catch {
            assertionFailure("Couldn't save comment \(comment.id): \(error)")
        }
    }

    func remove(_ id: Int) {
        do {
            try database.run("DELETE FROM saved_comments WHERE id = ?", [.init(id)])
            entries[id] = nil
            NotificationCenter.default.post(name: Self.didChange, object: id)
            onChange?(id)
        } catch {
            assertionFailure("Couldn't remove comment \(id): \(error)")
        }
    }

    /// Changes from another device, through iCloud.
    func applyRemote(saved: [SavedComment], removed: [Int]) throws {
        let removed = removed.filter { entries[$0] != nil }
        guard !saved.isEmpty || !removed.isEmpty else { return }
        try database.transaction {
            for entry in saved { try insert(entry) }
            for id in removed { try database.run("DELETE FROM saved_comments WHERE id = ?", [.init(id)]) }
        }
        for entry in saved { entries[entry.id] = entry }
        for id in removed { entries[id] = nil }
        let ids = saved.map(\.id) + removed
        NotificationCenter.default.post(name: Self.didChange, object: ids.count == 1 ? ids[0] : nil)
    }

    private func insert(_ entry: SavedComment) throws {
        try database.run(
            """
            INSERT OR REPLACE INTO saved_comments (id, story_id, story_title, author, text, posted_at, saved_at)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .init(entry.id), .init(entry.storyID), .init(entry.storyTitle), .init(entry.author),
                .text(entry.text), .init(entry.time), .init(entry.savedAt),
            ]
        )
    }

    private func loadEntries() throws -> [Int: SavedComment] {
        let rows = try database.query("""
            SELECT id, story_id, story_title, author, text, posted_at, saved_at FROM saved_comments
            """)
        let entries = rows.compactMap { row -> SavedComment? in
            guard let id = row.int(0), let text = row.string(4),
                  let postedAt = row.double(5), let savedAt = row.double(6)
            else { return nil }
            return SavedComment(
                id: id, author: row.string(3), text: text, time: Date(timeIntervalSince1970: postedAt),
                storyID: row.int(1), storyTitle: row.string(2), savedAt: Date(timeIntervalSince1970: savedAt)
            )
        }
        return Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { $1 })
    }
}
