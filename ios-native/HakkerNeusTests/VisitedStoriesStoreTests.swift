import Foundation
import Testing
@testable import HakkerNeus

@MainActor
struct VisitedStoriesStoreTests {
    private let databaseURL = FileManager.default.temporaryDirectory
        .appending(path: "VisitedStoriesStoreTests-\(UUID().uuidString)/HakkerNeus.sqlite")

    private func makeStore() throws -> VisitedStoriesStore {
        try VisitedStoriesStore(database: Database(url: databaseURL))
    }

    private func story(_ id: Int, comments: Int) -> Story {
        Story(id: id, title: "t", author: nil, url: nil, text: nil, score: 0, commentCount: comments, time: Date())
    }

    @Test func openingTheLinkMarksItReadWithoutCountingComments() throws {
        let store = try makeStore()
        store.markOpened(story(1, comments: 10))

        #expect(store.isVisited(1))
        #expect(!store.isVisited(2))
        #expect(store.newCommentCount(for: story(1, comments: 15)) == nil)
    }

    @Test func countsCommentsAddedSinceTheyWereLastOpened() throws {
        let store = try makeStore()
        store.markCommentsSeen(story(1, comments: 10))

        #expect(store.newCommentCount(for: story(1, comments: 10)) == nil)
        #expect(store.newCommentCount(for: story(1, comments: 14)) == 4)
        // Deleted comments can make the count drop; that's not "new".
        #expect(store.newCommentCount(for: story(1, comments: 8)) == nil)

        // Opening the link afterwards keeps the seen count.
        store.markOpened(story(1, comments: 14))
        #expect(store.newCommentCount(for: story(1, comments: 14)) == 4)
    }

    @Test func persists() throws {
        try makeStore().markCommentsSeen(story(1, comments: 3))

        let reloaded = try makeStore()
        #expect(reloaded.isVisited(1))
        #expect(reloaded.newCommentCount(for: story(1, comments: 5)) == 2)
    }

    @Test func sharesTheDatabaseWithSavedStories() throws {
        let database = try Database(url: databaseURL)
        let saved = try SavedStoriesStore(database: database, legacyDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        let visited = try VisitedStoriesStore(database: database)

        saved.save(story(1, comments: 0))
        visited.markOpened(story(1, comments: 0))

        #expect(database.userVersion == Schema.migrations.count)
        #expect(saved.isSaved(1) && visited.isVisited(1))
    }
}
