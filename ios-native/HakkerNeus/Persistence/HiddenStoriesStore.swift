import Foundation

/// Front-page stories hidden with the hide-read button. They stay hidden across refreshes;
/// only the most recent few thousand are kept, as old stories fall off the front page anyway.
@MainActor
final class HiddenStoriesStore {
    private let defaults: UserDefaults
    private let key = "hiddenStoryIDs"
    private let limit = 3000
    /// Oldest first.
    private var order: [Int]
    private var ids: Set<Int>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        order = defaults.array(forKey: key) as? [Int] ?? []
        ids = Set(order)
    }

    func isHidden(_ id: Int) -> Bool {
        ids.contains(id)
    }

    func hide(_ newIDs: [Int]) {
        let new = newIDs.filter { !ids.contains($0) }
        order.append(contentsOf: new)
        if order.count > limit { order.removeFirst(order.count - limit) }
        ids = Set(order)
        save()
    }

    func unhide(_ unhidden: [Int]) {
        let remove = Set(unhidden)
        order.removeAll { remove.contains($0) }
        ids.subtract(remove)
        save()
    }

    private func save() {
        defaults.set(order, forKey: key)
    }
}
