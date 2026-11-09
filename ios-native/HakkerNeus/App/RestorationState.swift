import UIKit

/// What was on screen, saved when the app goes to the background and used to rebuild the
/// screens on the next launch. Kept in UserDefaults rather than UIKit's scene restoration,
/// which discards its state whenever the app is closed from the app switcher.
///
/// Scroll positions are kept as an anchor (an item and how far its top was from the top of the
/// screen) rather than an offset, because content is reloaded and may have changed.
struct RestorationState: Codable, Equatable {
    struct ScrollAnchor: Codable, Equatable {
        var id: Int
        var offset: CGFloat
    }

    struct CommentsScreen: Codable, Equatable {
        var itemID: Int
        var story: Story?
        var anchor: ScrollAnchor?
        var collapsed: [Int]
    }

    var showsFrontPage = true
    /// The feed at the root of the stack (Top, New, Hottest or Newest), when it belongs to the
    /// site the app opens to; nil for that site's first.
    var rootFeed: TopStoriesFeed.Source?
    /// The front page as it was loaded, so it comes back unchanged rather than re-ranked.
    var frontPageFeed: TopStoriesFeed.Snapshot?
    var frontPageAnchor: ScrollAnchor?
    var savedListAnchor: ScrollAnchor?
    /// Comments screens on top of the lists, bottom to top.
    var comments: [CommentsScreen] = []

    private static let defaultsKey = "restorationState"

    func save(to defaults: UserDefaults = .standard) {
        defaults.set(try? JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }

    static func load(from defaults: UserDefaults = .standard) -> RestorationState? {
        defaults.data(forKey: defaultsKey).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    init(
        showsFrontPage: Bool = true,
        rootFeed: TopStoriesFeed.Source? = nil,
        frontPageFeed: TopStoriesFeed.Snapshot? = nil,
        frontPageAnchor: ScrollAnchor? = nil,
        savedListAnchor: ScrollAnchor? = nil,
        comments: [CommentsScreen] = []
    ) {
        self.showsFrontPage = showsFrontPage
        self.rootFeed = rootFeed
        self.frontPageFeed = frontPageFeed
        self.frontPageAnchor = frontPageAnchor
        self.savedListAnchor = savedListAnchor
        self.comments = comments
    }

}

extension UICollectionView {
    /// The first item at least partly below the top edge, and how far its top is from that edge.
    /// Nil when scrolled to the very top, where there's nothing to restore.
    var topAnchorItem: (indexPath: IndexPath, offset: CGFloat)? {
        let top = contentOffset.y + adjustedContentInset.top
        guard top > 1 else { return nil }
        return indexPathsForVisibleItems
            .compactMap { indexPath in layoutAttributesForItem(at: indexPath).map { (indexPath, $0.frame) } }
            .filter { $0.1.maxY > top }
            .min { $0.1.minY < $1.1.minY }
            .map { ($0.0, $0.1.minY - top) }
    }

    /// Scrolls so the item's top is `offset` below the top edge again.
    func scroll(toAnchor indexPath: IndexPath, offset: CGFloat) {
        layoutIfNeeded()
        scrollToItem(at: indexPath, at: .top, animated: false)
        layoutIfNeeded()
        let minY = -adjustedContentInset.top
        let maxY = max(minY, contentSize.height + adjustedContentInset.bottom - bounds.height)
        contentOffset.y = min(max(contentOffset.y - offset, minY), maxY)
    }
}
