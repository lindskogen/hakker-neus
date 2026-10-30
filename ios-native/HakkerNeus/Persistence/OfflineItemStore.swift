import Foundation

/// Copies of recently loaded comment threads, so a story's comments can still be shown when
/// the network isn't there. Kept for a week.
@MainActor
final class OfflineItemStore {
    static let maxAge: TimeInterval = 7 * 24 * 3600

    private let database: Database

    init(database: Database) throws {
        self.database = database
        try Schema.migrate(database)
        try? database.run("DELETE FROM item_cache WHERE fetched_at < ?", [.init(Date().addingTimeInterval(-Self.maxAge))])
    }

    func save(_ item: StoryWithComments, id: Int, at date: Date = Date()) {
        guard let data = try? JSONEncoder().encode(item), let json = String(data: data, encoding: .utf8) else { return }
        try? database.run(
            "INSERT OR REPLACE INTO item_cache (id, json, fetched_at) VALUES (?, ?, ?)",
            [.init(id), .text(json), .init(date)]
        )
    }

    /// The saved copy and when it was fetched, if there is one younger than `maxAge`.
    func item(id: Int, now: Date = Date()) -> (item: StoryWithComments, fetchedAt: Date)? {
        guard let row = try? database.query("SELECT json, fetched_at FROM item_cache WHERE id = ?", [.init(id)]).first,
              let json = row.string(0), let fetchedAt = row.double(1)
        else { return nil }
        let date = Date(timeIntervalSince1970: fetchedAt)
        guard now.timeIntervalSince(date) < Self.maxAge,
              let item = try? JSONDecoder().decode(StoryWithComments.self, from: Data(json.utf8))
        else { return nil }
        return (item, date)
    }
}
