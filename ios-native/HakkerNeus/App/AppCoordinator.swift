import SafariServices
import UIKit

/// Owns app-wide dependencies, the root navigation stack, and navigation between screens.
@MainActor
final class AppCoordinator {
    private let window: UIWindow
    private let navigationController = NavigationController()
    private var relativeTimeTimer: Timer?

    let client: HNClient
    let itemCache: ItemCache
    let savedStories: SavedStoriesStore

    init(
        window: UIWindow,
        client: HNClient = LiveHNClient(),
        savedStories: SavedStoriesStore = SavedStoriesStore()
    ) {
        self.window = window
        #if DEBUG
        let client = ProcessInfo.processInfo.arguments.contains(CommentsSinkClient.launchArgument)
            ? CommentsSinkClient(base: client) : client
        #endif
        self.client = client
        self.itemCache = ItemCache(client: client)
        self.savedStories = savedStories
    }

    func start() {
        let root = StoryListViewController(feed: TopStoriesFeed(client: client), coordinator: self)
        navigationController.setViewControllers([root], animated: false)

        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        #if DEBUG
        if client is CommentsSinkClient {
            showComments(id: CommentsSinkClient.itemID)
        }
        #endif

        relativeTimeTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            NotificationCenter.default.post(name: RelativeTime.tick, object: nil)
        }
    }

    // MARK: Navigation

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
        if let id = url.hackerNewsItemID {
            showComments(id: id)
        } else {
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

    func showUser(_ username: String) {
        var components = URLComponents(string: "https://news.ycombinator.com/user")!
        components.queryItems = [URLQueryItem(name: "id", value: username)]
        open(components.url!)
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

extension URL {
    /// The item ID of a `news.ycombinator.com/item?id=…` link.
    var hackerNewsItemID: Int? {
        guard let host = host(), host == "news.ycombinator.com" || host.hasSuffix(".news.ycombinator.com"),
              path() == "/item",
              let components = URLComponents(url: self, resolvingAgainstBaseURL: false)
        else { return nil }
        return components.queryItems?.first { $0.name == "id" }?.value.flatMap { Int($0) }
    }
}

/// Navigation controller with a hidden bar that keeps the interactive swipe-back gestures.
///
/// UIKit disables both pop gestures while the bar is hidden. Taking over their delegates
/// re-enables them: the edge swipe everywhere, and on iOS 26 also the swipe from anywhere in
/// the content area. iOS 18–25 only get the edge swipe.
final class NavigationController: UINavigationController, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        view.backgroundColor = Theme.Color.backgroundDark

        interactivePopGestureRecognizer?.delegate = self
        if #available(iOS 26, *) {
            // Apple documents this recognizer as "only for failure requirements", so this may need
            // revisiting in future iOS versions. Covered by NavigationUITests.
            interactiveContentPopGestureRecognizer?.delegate = self
        }
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard #available(iOS 26, *), gestureRecognizer === interactiveContentPopGestureRecognizer else { return true }

        // Inside a sideways-scrolled view (a code block), dragging right scrolls it back instead.
        var view = touch.view
        while let current = view {
            if let scrollView = current as? UIScrollView,
               scrollView.contentSize.width > scrollView.bounds.width,
               scrollView.contentOffset.x > -scrollView.adjustedContentInset.left {
                return false
            }
            view = current.superview
        }
        return true
    }
}
