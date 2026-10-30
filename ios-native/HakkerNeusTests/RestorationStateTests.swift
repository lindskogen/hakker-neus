import Foundation
import Testing
@testable import HakkerNeus

struct RestorationStateTests {
    @Test func roundTripsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let state = RestorationState(
            showsFrontPage: false,
            frontPageFeed: .init(ids: [1, 2, 3], nextOffset: 2, stories: [.stub(id: 1), .stub(id: 2)]),
            frontPageAnchor: .init(id: 1, offset: -12.5),
            savedListAnchor: nil,
            comments: [
                .init(itemID: 10, story: .stub(id: 10), anchor: .init(id: 11, offset: 40), collapsed: [12, 13]),
                .init(itemID: 20, story: nil, anchor: nil, collapsed: []),
            ]
        )

        state.save(to: defaults)
        #expect(RestorationState.load(from: defaults) == state)
    }

    @Test func nothingSavedMeansNothingToRestore() {
        #expect(RestorationState.load(from: UserDefaults(suiteName: UUID().uuidString)!) == nil)
    }
}
