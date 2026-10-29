import Foundation
import Testing
@testable import HakkerNeus

@MainActor
struct SavedStoriesStoreTests {
    private let databaseURL = FileManager.default.temporaryDirectory
        .appending(path: "SavedStoriesStoreTests-\(UUID().uuidString)/HakkerNeus.sqlite")
    private let suiteName = "SavedStoriesStoreTests-\(UUID().uuidString)"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeStore(_ defaults: UserDefaults) throws -> SavedStoriesStore {
        try SavedStoriesStore(database: Database(url: databaseURL), legacyDefaults: defaults)
    }

    @Test func togglesAndPersists() throws {
        let defaults = makeDefaults()
        let store = try makeStore(defaults)

        #expect(store.toggle(.stub(id: 1)))
        #expect(store.toggle(.stub(id: 2)))
        #expect(!store.toggle(.stub(id: 1)))

        let reloaded = try makeStore(defaults)
        #expect(!reloaded.isSaved(1))
        #expect(reloaded.isSaved(2))
        #expect(reloaded.all == [.stub(id: 2)])
    }

    @Test func roundTripsEveryField() throws {
        let defaults = makeDefaults()
        let story = Story(
            id: 42, title: "Ask HN: “Quotes” & ‘ünicode’", author: nil, url: nil,
            text: "Some <i>HTML</i>", score: 7, commentCount: 3, time: Date(timeIntervalSince1970: 1_700_000_000.5)
        )
        try makeStore(defaults).save(story)

        #expect(try makeStore(defaults).all == [story])
    }

    @Test func newestSavedFirst() throws {
        let store = try makeStore(makeDefaults())
        store.save(.stub(id: 1), at: Date(timeIntervalSince1970: 300))
        store.save(.stub(id: 2), at: Date(timeIntervalSince1970: 100))
        store.save(.stub(id: 3), at: Date(timeIntervalSince1970: 200))

        #expect(store.all.map(\.id) == [1, 3, 2])
    }

    @Test func importsUserDefaultsFromEarlierBuildsOnce() throws {
        let defaults = makeDefaults()
        let legacy: [Int: Story] = [1: .stub(id: 1), 2: .stub(id: 2)]
        defaults.set(try JSONEncoder().encode(legacy), forKey: "savedStories")

        let store = try makeStore(defaults)

        // No saved date before, so the story's own time stands in for it.
        #expect(store.all.map(\.id) == [2, 1])
        #expect(defaults.data(forKey: "savedStories") == nil)
        #expect(try makeStore(defaults).all.map(\.id) == [2, 1])
    }
}
