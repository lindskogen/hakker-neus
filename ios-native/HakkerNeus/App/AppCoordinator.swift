import SafariServices
import UIKit

/// Owns app-wide dependencies, the root navigation stack, and navigation between screens.
///
/// The stack starts as [Saved, Front page]: the saved list sits "behind" the front page,
/// so the edge swipe back from the front page reveals it.
@MainActor
final class AppCoordinator {
    let window: UIWindow
    let navigationController = NavigationController()
    private var relativeTimeTimer: Timer?
    let defaults: UserDefaults

    let client: HNClient
    let itemCache: ItemCache
    let savedStories: SavedStoriesStore

    /// Kept alive while the saved list is showing, so its scroll position and pages survive.
    private(set) lazy var frontPage = StoryListViewController(feed: TopStoriesFeed(client: client), coordinator: self)
    private lazy var savedList = SavedStoriesViewController(coordinator: self)

    init(
        window: UIWindow,
        client: HNClient = LiveHNClient(),
        savedStories: SavedStoriesStore? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.window = window
        #if DEBUG
        let client = ProcessInfo.processInfo.arguments.contains(CommentsSinkClient.launchArgument)
            ? CommentsSinkClient(base: client) : client
        #endif
        self.client = client
        self.itemCache = ItemCache(client: client)
        self.defaults = defaults
        self.savedStories = savedStories ?? Self.makeSavedStoriesStore(defaults: defaults)
    }

    private static func makeSavedStoriesStore(defaults: UserDefaults) -> SavedStoriesStore {
        do {
            let url = URL.applicationSupportDirectory.appending(path: "HakkerNeus.sqlite")
            return try SavedStoriesStore(database: Database(url: url), legacyDefaults: defaults)
        } catch {
            fatalError("Couldn't open the database: \(error)")
        }
    }

    func start() {
        navigationController.setViewControllers([savedList, frontPage], animated: false)

        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        #if DEBUG
        if client is CommentsSinkClient {
            showComments(id: CommentsSinkClient.itemID)
        }
        #endif

        NotificationCenter.default.addObserver(
            forName: SavedStoriesStore.didChange, object: nil, queue: .main
        ) { [weak self] notification in
            let id = notification.object as? Int
            MainActor.assumeIsolated { self?.savedStoryChanged(id) }
        }

        relativeTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            NotificationCenter.default.post(name: RelativeTime.tick, object: nil)
        }
    }

    // MARK: Navigation

    /// The Home Screen quick action that opens the saved list.
    static let savedStoriesShortcut = "se.lindskogen.hakkerneues.saved"

    func handleShortcut(_ type: String) -> Bool {
        guard type == Self.savedStoriesShortcut else { return false }
        navigationController.presentedViewController?.dismiss(animated: false)
        showSavedStories(animated: false)
        return true
    }

    func showSavedStories(animated: Bool = true) {
        navigationController.popToRootViewController(animated: animated)
    }

    func showFrontPage(animated: Bool = true) {
        if navigationController.viewControllers.contains(frontPage) {
            navigationController.popToViewController(frontPage, animated: animated)
        } else {
            navigationController.pushViewController(frontPage, animated: animated)
        }
    }

    func makeCommentsViewController(id: Int, story: Story?) -> CommentsViewController {
        itemCache.prefetch(id: id)
        return CommentsViewController(id: id, story: story, coordinator: self)
    }

    func showComments(for story: Story) {
        navigationController.pushViewController(makeCommentsViewController(id: story.id, story: story), animated: true)
    }

    func showComments(id: Int) {
        navigationController.pushViewController(makeCommentsViewController(id: id, story: nil), animated: true)
    }

    /// Opens HN item links in the app and everything else in an in-app browser.
    func open(_ url: URL) {
        switch HackerNewsLink(url) {
        case .item(let id):
            showComments(id: id)
        case .user(let username):
            showUser(username)
        case nil:
            navigationController.present(makeBrowser(for: url), animated: true)
        }
    }

    func makeBrowser(for url: URL) -> SFSafariViewController {
        let browser = SFSafariViewController(url: url)
        browser.preferredBarTintColor = Theme.Color.backgroundDark
        browser.preferredControlTintColor = .white
        browser.dismissButtonStyle = .done
        return browser
    }

    /// There's no native profile screen yet, so profiles open on HN in the browser.
    func showUser(_ username: String) {
        var components = URLComponents(string: "https://news.ycombinator.com/user")!
        components.queryItems = [URLQueryItem(name: "id", value: username)]
        navigationController.present(makeBrowser(for: components.url!), animated: true)
    }

    func share(_ url: URL, from sourceView: UIView) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sourceView
        navigationController.present(activity, animated: true)
    }

    // MARK: Context menu previews

    /// Preview for long-pressing a story: the linked page, or the comments for self posts.
    func makePreview(for story: Story) -> UIViewController {
        if let url = story.url {
            makeBrowser(for: url)
        } else {
            makeCommentsViewController(id: story.id, story: story)
        }
    }

    /// Called when the user taps a context menu preview to open it fully.
    func commitPreview(_ viewController: UIViewController) {
        if viewController is SFSafariViewController {
            navigationController.present(viewController, animated: true)
        } else {
            navigationController.pushViewController(viewController, animated: true)
        }
    }

    // MARK: Menus

    func storyMenu(for story: Story, sourceView: UIView, includeComments: Bool) -> UIMenu {
        var open: [UIMenuElement] = []
        if includeComments {
            open.append(UIAction(
                title: "Comments",
                subtitle: story.commentCount == 1 ? "1 comment" : "\(story.commentCount) comments",
                image: UIImage(systemName: "bubble.left.and.bubble.right")
            ) { [weak self] _ in
                self?.showComments(for: story)
            })
        }
        if let url = story.url {
            open.append(UIAction(title: "Open Link", subtitle: url.host(), image: UIImage(systemName: "safari")) { [weak self] _ in
                self?.open(url)
            })
        }

        let isSaved = savedStories.isSaved(story.id)
        let save = UIAction(
            title: isSaved ? "Unsave" : "Save",
            image: UIImage(systemName: isSaved ? "heart.slash" : "heart")
        ) { [weak self] _ in
            self?.savedStories.toggle(story)
        }

        let shareURL = story.url ?? story.hackerNewsURL
        let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self, weak sourceView] _ in
            guard let sourceView else { return }
            self?.share(shareURL, from: sourceView)
        }
        let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
            UIPasteboard.general.url = shareURL
        }

        var user: [UIMenuElement] = []
        if let author = story.author {
            user.append(UIAction(title: author, image: UIImage(systemName: "person")) { [weak self] _ in
                self?.showUser(author)
            })
        }

        return UIMenu(children: [
            UIMenu(options: .displayInline, children: open),
            UIMenu(options: .displayInline, children: [save, share, copy]),
            UIMenu(options: .displayInline, children: user),
        ])
    }
}

/// A Hacker News link the app can show itself.
enum HackerNewsLink: Equatable {
    case item(Int)
    case user(String)

    static let base = URL(string: "https://news.ycombinator.com/")!

    /// Recognizes `news.ycombinator.com/item?id=…` and `/user?id=…`, including the bare
    /// `ycombinator.com` host. Anything else on HN (or elsewhere) is left to the browser.
    init?(_ url: URL) {
        guard let host = url.host()?.lowercased(),
              ["news.ycombinator.com", "ycombinator.com", "www.ycombinator.com"].contains(host),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let value = components.queryItems?.first(where: { $0.name == "id" })?.value, !value.isEmpty
        else { return nil }

        switch components.path {
        case "/item":
            guard let id = Int(value) else { return nil }
            self = .item(id)
        case "/user":
            self = .user(value)
        default:
            return nil
        }
    }
}
