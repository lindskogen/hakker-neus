import Foundation

/// Stories the user has saved with the swipe-right gesture (`useSaveStory.ts`).
/// Whole stories are stored, not just IDs, so a saved list can be shown offline later.
@MainActor
final class SavedStoriesStore {
    private let defaults: UserDefaults
    private let key = "savedStories"
    private var stories: [Int: Story]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        stories = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([Int: Story].self, from: $0) } ?? [:]
    }

    var all: [Story] {
        stories.values.sorted { $0.time > $1.time }
    }

    func isSaved(_ id: Int) -> Bool {
        stories[id] != nil
    }

    func save(_ story: Story) {
        stories[story.id] = story
        persist()
    }

    func remove(_ id: Int) {
        stories[id] = nil
        persist()
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

    private func persist() {
        if let data = try? JSONEncoder().encode(stories) {
            defaults.set(data, forKey: key)
        }
    }
}
