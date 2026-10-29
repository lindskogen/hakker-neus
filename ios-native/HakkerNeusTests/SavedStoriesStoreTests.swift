import Foundation
import Testing
@testable import HakkerNeus

@MainActor
struct SavedStoriesStoreTests {
    private let suiteName = "SavedStoriesStoreTests-\(UUID().uuidString)"

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    @Test func togglesAndPersists() {
        let defaults = makeDefaults()
        let store = SavedStoriesStore(defaults: defaults)

        #expect(store.toggle(.stub(id: 1)))
        #expect(store.toggle(.stub(id: 2)))
        #expect(!store.toggle(.stub(id: 1)))

        let reloaded = SavedStoriesStore(defaults: defaults)
        #expect(!reloaded.isSaved(1))
        #expect(reloaded.isSaved(2))
        #expect(reloaded.all == [.stub(id: 2)])
    }
}
