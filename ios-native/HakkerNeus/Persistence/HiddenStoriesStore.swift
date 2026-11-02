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
    /// Called with each story hidden or unhidden on this device (not from iCloud).
    var onChange: ((Int) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        order = defaults.array(forKey: key) as? [Int] ?? []
        ids = Set(order)
    }

    func isHidden(_ id: Int) -> Bool {
        ids.contains(id)
    }

    /// Oldest first.
    var allIDs: [Int] { order }

    func hide(_ newIDs: [Int]) {
        let new = add(newIDs)
        new.forEach { onChange?($0) }
    }

    func unhide(_ unhidden: [Int]) {
        let removed = remove(unhidden)
        removed.forEach { onChange?($0) }
    }

    /// Changes from another device, through iCloud.
    func applyRemote(hidden: [Int], unhidden: [Int]) {
        add(hidden)
        remove(unhidden)
    }

    @discardableResult
    private func add(_ newIDs: [Int]) -> [Int] {
        let new = Array(NSOrderedSet(array: newIDs.filter { !ids.contains($0) })) as? [Int] ?? []
        guard !new.isEmpty else { return [] }
        order.append(contentsOf: new)
        if order.count > limit { order.removeFirst(order.count - limit) }
        ids = Set(order)
        save()
        return new
    }

    @discardableResult
    private func remove(_ unhidden: [Int]) -> [Int] {
        let removed = Set(unhidden).intersection(ids)
        guard !removed.isEmpty else { return [] }
        order.removeAll { removed.contains($0) }
        ids.subtract(removed)
        save()
        return Array(removed)
    }

    private func save() {
        defaults.set(order, forKey: key)
    }
}
