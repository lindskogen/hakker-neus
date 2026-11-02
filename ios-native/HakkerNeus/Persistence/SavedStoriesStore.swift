import Foundation

/// Stories the user has saved (`useSaveStory.ts`), newest first, kept in the app's SQLite database.
/// Whole stories are stored, not just IDs, so the saved list works offline.
/// Reads come from an in-memory copy loaded at startup; writes go straight to the database.
@MainActor
final class SavedStoriesStore {
    /// Posted after a story is saved or removed. `object` is the story ID as an `Int`.
    static let didChange = Notification.Name("SavedStoriesStore.didChange")

    struct Entry: Equatable {
        let story: Story
        let savedAt: Date
    }

    private let database: Database
    private var entries: [Int: Entry] = [:]
    /// Called with the story ID after a change made on this device (not one from iCloud).
    var onChange: ((Int) -> Void)?

    /// - Parameters:
    ///   - database: The app database; the saved stories table is created if needed.
    ///   - legacyDefaults: Where earlier builds kept saved stories; migrated once, then cleared.
    init(database: Database, legacyDefaults: UserDefaults = .standard) throws {
        self.database = database
        try Schema.migrate(database)
        try importLegacy(from: legacyDefaults)
        entries = try loadEntries()
    }

    /// Most recently saved first, with when each was saved.
    var allEntries: [Entry] {
        entries.values.sorted { $0.savedAt > $1.savedAt }
    }

    /// Adds stories from an import. Stories already saved are kept, with the earlier saved date.
    /// Returns how many were new and how many were already saved.
    @discardableResult
    func merge(_ imported: [Entry]) throws -> (added: Int, alreadySaved: Int) {
        var added = 0
        var alreadySaved = 0
        var merged = entries
        try database.transaction {
            for entry in imported {
                if let existing = merged[entry.story.id] {
                    alreadySaved += 1
                    guard entry.savedAt < existing.savedAt else { continue }
                    let earlier = Entry(story: existing.story, savedAt: entry.savedAt)
                    try insert(earlier)
                    merged[entry.story.id] = earlier
                } else {
                    added += 1
                    try insert(entry)
                    merged[entry.story.id] = entry
                }
            }
        }
        for (id, entry) in merged where entries[id] != entry { onChange?(id) }
        entries = merged
        // No single ID: lists refresh everything.
        NotificationCenter.default.post(name: Self.didChange, object: nil)
        return (added, alreadySaved)
    }

    /// Most recently saved first.
    var all: [Story] {
        entries.values.sorted { $0.savedAt > $1.savedAt }.map(\.story)
    }

    var isEmpty: Bool { entries.isEmpty }

    func isSaved(_ id: Int) -> Bool {
        entries[id] != nil
    }

    func entry(_ id: Int) -> Entry? {
        entries[id]
    }

    func save(_ story: Story, at date: Date = Date()) {
        let entry = Entry(story: story, savedAt: date)
        do {
            try insert(entry)
            entries[story.id] = entry
            NotificationCenter.default.post(name: Self.didChange, object: story.id)
            onChange?(story.id)
        } catch {
            assertionFailure("Couldn't save story \(story.id): \(error)")
        }
    }

    func remove(_ id: Int) {
        do {
            try database.run("DELETE FROM saved_stories WHERE id = ?", [.init(id)])
            entries[id] = nil
            NotificationCenter.default.post(name: Self.didChange, object: id)
            onChange?(id)
        } catch {
            assertionFailure("Couldn't remove story \(id): \(error)")
        }
    }

    /// Returns whether the story is saved afterwards.
    @discardableResult
    func toggle(_ story: Story) -> Bool {
        if isSaved(story.id) {
            remove(story.id)
            return false
        }
        save(story)
        return true
    }

    /// Changes from another device, through iCloud.
    func applyRemote(saved: [Entry], removed: [Int]) throws {
        let removed = removed.filter { entries[$0] != nil }
        guard !saved.isEmpty || !removed.isEmpty else { return }
        try database.transaction {
            for entry in saved { try insert(entry) }
            for id in removed { try database.run("DELETE FROM saved_stories WHERE id = ?", [.init(id)]) }
        }
        for entry in saved { entries[entry.story.id] = entry }
        for id in removed { entries[id] = nil }
        let ids = saved.map(\.story.id) + removed
        NotificationCenter.default.post(name: Self.didChange, object: ids.count == 1 ? ids[0] : nil)
    }

    // MARK: SQL

    private func insert(_ entry: Entry) throws {
        let story = entry.story
        try database.run(
            """
            INSERT OR REPLACE INTO saved_stories
                (id, title, author, url, text, score, comment_count, posted_at, saved_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            [
                .init(story.id), .text(story.title), .init(story.author), .init(story.url?.absoluteString),
                .init(story.text), .init(story.score), .init(story.commentCount), .init(story.time), .init(entry.savedAt),
            ]
        )
    }

    private func loadEntries() throws -> [Int: Entry] {
        let rows = try database.query("""
            SELECT id, title, author, url, text, score, comment_count, posted_at, saved_at FROM saved_stories
            """)
        let entries = rows.compactMap { row -> Entry? in
            guard let id = row.int(0), let title = row.string(1),
                  let postedAt = row.double(7), let savedAt = row.double(8)
            else { return nil }
            let story = Story(
                id: id,
                title: title,
                author: row.string(2),
                url: row.string(3).flatMap(URL.init(string:)),
                text: row.string(4),
                score: row.int(5) ?? 0,
                commentCount: row.int(6) ?? 0,
                time: Date(timeIntervalSince1970: postedAt)
            )
            return Entry(story: story, savedAt: Date(timeIntervalSince1970: savedAt))
        }
        return Dictionary(entries.map { ($0.story.id, $0) }, uniquingKeysWith: { $1 })
    }

    // MARK: Legacy

    private static let legacyKey = "savedStories"

    /// Earlier builds stored `[id: Story]` JSON in UserDefaults without a saved date;
    /// the story's own time stands in for it.
    private func importLegacy(from defaults: UserDefaults) throws {
        guard let data = defaults.data(forKey: Self.legacyKey) else { return }
        let stories = (try? JSONDecoder().decode([Int: Story].self, from: data)) ?? [:]
        try database.transaction {
            for story in stories.values {
                try insert(Entry(story: story, savedAt: story.time))
            }
        }
        defaults.removeObject(forKey: Self.legacyKey)
    }
}
