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

    /// - Parameters:
    ///   - database: The app database; the saved stories table is created if needed.
    ///   - legacyDefaults: Where earlier builds kept saved stories; migrated once, then cleared.
    init(database: Database, legacyDefaults: UserDefaults = .standard) throws {
        self.database = database
        try Self.migrateSchema(database)
        try importLegacy(from: legacyDefaults)
        entries = try loadEntries()
    }

    /// Most recently saved first.
    var all: [Story] {
        entries.values.sorted { $0.savedAt > $1.savedAt }.map(\.story)
    }

    var isEmpty: Bool { entries.isEmpty }

    func isSaved(_ id: Int) -> Bool {
        entries[id] != nil
    }

    func save(_ story: Story, at date: Date = Date()) {
        let entry = Entry(story: story, savedAt: date)
        do {
            try insert(entry)
            entries[story.id] = entry
            NotificationCenter.default.post(name: Self.didChange, object: story.id)
        } catch {
            assertionFailure("Couldn't save story \(story.id): \(error)")
        }
    }

    func remove(_ id: Int) {
        do {
            try database.run("DELETE FROM saved_stories WHERE id = ?", [.init(id)])
            entries[id] = nil
            NotificationCenter.default.post(name: Self.didChange, object: id)
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

    // MARK: SQL

    private static func migrateSchema(_ database: Database) throws {
        if database.userVersion < 1 {
            try database.transaction {
                try database.execute("""
                    CREATE TABLE IF NOT EXISTS saved_stories (
                        id INTEGER PRIMARY KEY,
                        title TEXT NOT NULL,
                        author TEXT,
                        url TEXT,
                        text TEXT,
                        score INTEGER NOT NULL,
                        comment_count INTEGER NOT NULL,
                        posted_at REAL NOT NULL,
                        saved_at REAL NOT NULL
                    );
                    CREATE INDEX IF NOT EXISTS saved_stories_saved_at ON saved_stories (saved_at DESC);
                    """)
                try database.setUserVersion(1)
            }
        }
    }

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
