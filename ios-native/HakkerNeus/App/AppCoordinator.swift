import SafariServices
import UIKit
import os

/// Owns app-wide dependencies, the root navigation stack, and navigation between screens.
///
/// The stack starts as [Saved, Front page]: the saved list sits "behind" the front page,
/// so the edge swipe back from the front page reveals it.
@MainActor
final class AppCoordinator {
    let window: UIWindow
    let navigationController = NavigationController()
    /// The root: `navigationController` alone, or beside a column for articles and comments when the window is wide.
    private(set) lazy var split = SplitViewController(primary: navigationController)

    /// Where a screen is opened from, which decides where it goes when the window is wide:
    /// from a list it replaces what's in the side column, from the side column it goes on top.
    enum OpenedFrom {
        case list
        case detail
    }
    private var relativeTimeTimer: Timer?
    let defaults: UserDefaults

    let client: HNClient
    let itemCache: ItemCache
    let savedStories: SavedStoriesStore
    let savedComments: SavedCommentsStore
    let visitedStories: VisitedStoriesStore
    let hiddenStories: HiddenStoriesStore
    let offlineItems: OfflineItemStore
    /// Nil in tests, which bring their own database.
    let cloudSync: CloudSync?
    let settings: AppSettings
    let nitter: NitterRedirect
    let session = HNSession()
    let userCache = UserCache(api: UserAPI(transport: URLSession.shared))
    /// Unsent comment drafts, by the ID of what they reply to.
    var drafts: [Int: String] = [:]

    /// Kept alive while the saved list is showing, so its scroll position and pages survive.
    private(set) lazy var frontPage = StoryListViewController(feed: TopStoriesFeed(client: client), coordinator: self)
    private(set) lazy var savedList = SavedStoriesViewController(coordinator: self)
    /// Story search, kept alive so the query and results survive going back.
    private(set) lazy var search = SearchViewController(coordinator: self, api: userCache.api)
    /// HN's New list, kept alive like the front page so its place survives going back and forth.
    private(set) lazy var newList = StoryListViewController(feed: TopStoriesFeed(client: client, source: .new), coordinator: self)
    /// lobste.rs's Hottest list, read-only, opened from the saved list like search.
    private(set) lazy var lobstersList = StoryListViewController(
        feed: TopStoriesFeed(client: client, source: .lobsters), coordinator: self, rowBackground: { Palette.lobstersBackground(at: $0) }
    )

    init(
        window: UIWindow,
        client: HNClient = LiveHNClient(),
        database: Database? = nil,
        defaults: UserDefaults = .standard
    ) {
        self.window = window
        #if DEBUG
        let client = ProcessInfo.processInfo.arguments.contains(CommentsSinkClient.launchArgument)
            ? CommentsSinkClient(base: client) : client
        #endif
        // lobste.rs items (negative IDs) go to lobste.rs, everything else to HN.
        let routing = SourceRoutingClient(hn: client)
        self.client = routing
        self.itemCache = ItemCache(client: routing)
        _ = NetworkConditions.shared // Start watching the connection before it's asked about.
        self.defaults = defaults
        self.settings = AppSettings(defaults: defaults)
        self.nitter = NitterRedirect(settings: settings)
        self.hiddenStories = HiddenStoriesStore(defaults: defaults)
        ColorTheme.current = settings.colorTheme
        CommentTextStyle.current = settings.commentTextStyle
        do {
            let injectedDatabase = database
            let database = try database ?? Database(url: URL.applicationSupportDirectory.appending(path: "HakkerNeus.sqlite"))
            self.savedStories = try SavedStoriesStore(database: database, legacyDefaults: defaults)
            self.savedComments = try SavedCommentsStore(database: database)
            self.visitedStories = try VisitedStoriesStore(database: database)
            self.offlineItems = try OfflineItemStore(database: database)
            let isTesting = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            self.cloudSync = injectedDatabase == nil && !isTesting ? try CloudSync(
                database: database, savedStories: savedStories, savedComments: savedComments,
                visitedStories: visitedStories, hiddenStories: hiddenStories
            ) : nil
        } catch {
            fatalError("Couldn't open the database: \(error)")
        }
    }

    #if DEBUG
    /// Debug builds import a `seed_bookmarks.csv` dropped into the app's Documents folder
    /// (e.g. with `xcrun devicectl device copy to`), then delete it.
    private func importSeedBookmarks() {
        let url = URL.documentsDirectory.appending(path: "seed_bookmarks.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let result = BookmarksCSV.read(text)
        let merged = try? savedStories.merge(result.entries)
        try? FileManager.default.removeItem(at: url)
        NSLog("Seeded saved stories from %@: %@, skipped %d", url.lastPathComponent, String(describing: merged), result.skipped)
    }
    #endif

    /// - Parameter state: Screens to restore from the previous launch, if any.
    func start(restoring state: RestorationState? = nil) {
        cloudSync?.start()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-SeedCloudKitSchema"), let cloudSync {
            Task { try await cloudSync.seedSchema() }
        }
        #endif
        #if DEBUG
        importSeedBookmarks()
        #endif
        var stack: [UIViewController] = [savedList]
        if state?.showsFrontPage ?? true {
            stack.append(frontPage)
        }
        savedList.pendingAnchor = state?.savedListAnchor
        if let feed = state?.frontPageFeed {
            frontPage.restoreFeed(feed)
        }
        frontPage.pendingAnchor = state?.frontPageAnchor
        for screen in state?.comments ?? [] {
            itemCache.prefetch(id: screen.itemID)
            stack.append(CommentsViewController(id: screen.itemID, story: screen.story, coordinator: self, restoring: screen))
        }
        navigationController.cornerButtonMode = { [weak self] screen in
            guard let self else { return .hidden }
            if screen === frontPage { return .menu }
            if screen === savedList || screen === newList || screen === lobstersList { return .close }
            return .hidden
        }
        navigationController.cornerButtonOnLeft = settings.cornerButtonOnLeft
        NotificationCenter.default.addObserver(forName: AppSettings.cornerButtonSideDidChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.navigationController.cornerButtonOnLeft = self.settings.cornerButtonOnLeft
            }
        }
        navigationController.onCornerButton = { [weak self] screen in
            guard let self else { return }
            screen === savedList || screen === newList || screen === lobstersList ? showFrontPage() : showSavedStories()
        }
        navigationController.setViewControllers(stack, animated: false)
        navigationController.updateCornerButton(for: stack.last, animated: false)

        split.isList = { $0 is StoryListViewController || $0 is SavedStoriesViewController || $0 is SearchViewController }
        window.rootViewController = split
        window.makeKeyAndVisible()
        // Lay out now, so links opened at launch know whether there's room beside the list.
        split.view.layoutIfNeeded()
        if !settings.opensLinksInSafari { AdBlocking.prepare() }
        nitter.prepare()

        #if DEBUG
        if (client as? SourceRoutingClient)?.hn is CommentsSinkClient {
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

    /// What's on screen now, for the next launch.
    var restorationState: RestorationState {
        let stack = split.allViewControllers
        return RestorationState(
            showsFrontPage: stack.contains(frontPage),
            frontPageFeed: frontPage.feedSnapshot,
            frontPageAnchor: frontPage.scrollAnchor,
            savedListAnchor: savedList.scrollAnchor,
            comments: stack.compactMap { ($0 as? CommentsViewController)?.restorationState }
        )
    }

    // MARK: Navigation

    /// `hakkerneus://item?id=123` opens an item; `hakkerneus://open?url=<HN or other link>`
    /// opens a link the way a tap in a comment would. For other apps and Shortcuts, since
    /// universal links for news.ycombinator.com would need HN's cooperation.
    @discardableResult
    func handleAppURL(_ url: URL) -> Bool {
        guard url.scheme == "hakkerneus",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return false }
        let query = components.queryItems ?? []
        navigationController.presentedViewController?.dismiss(animated: false)
        switch url.host() {
        case "item":
            guard let id = query.first(where: { $0.name == "id" })?.value.flatMap({ Int($0) }) else { return false }
            showComments(id: id)
        case "open":
            guard let link = query.first(where: { $0.name == "url" })?.value.flatMap(URL.init(string:)) else { return false }
            open(link)
        case "user":
            guard let name = query.first(where: { $0.name == "id" })?.value, !name.isEmpty else { return false }
            showUser(name)
        case "search":
            // From the "Search on HN" share action, usually with a page's link.
            showSearch(query: query.first(where: { $0.name == "q" })?.value ?? "")
        default:
            return false
        }
        return true
    }

    /// The Home Screen quick action that opens the saved list.
    static let savedStoriesShortcut = "se.lindskogen.hakkerneues.saved"

    func handleShortcut(_ type: String) -> Bool {
        guard type == Self.savedStoriesShortcut else { return false }
        navigationController.presentedViewController?.dismiss(animated: false)
        showSavedStories(animated: false)
        return true
    }

    /// The topmost presented screen, to present over.
    private var topViewController: UIViewController {
        var top: UIViewController = split
        while let presented = top.presentedViewController { top = presented }
        return top
    }

    /// Presents the sign-in screen over whatever is showing.
    /// - Parameter then: Runs after a successful sign-in.
    func showSignIn(then: (() -> Void)? = nil) {
        let screen = SignInViewController(coordinator: self)
        screen.onSignedIn = then
        let signIn = UINavigationController(rootViewController: screen)
        signIn.overrideUserInterfaceStyle = .dark
        topViewController.present(signIn, animated: true)
    }

    /// Opens the composer, signing in first if needed.
    func compose(_ target: ComposeViewController.Target, onPosted: @escaping (Comment) -> Void) {
        guard session.isSignedIn else {
            showSignIn { [weak self] in self?.compose(target, onPosted: onPosted) }
            return
        }
        let compose = UINavigationController(rootViewController: ComposeViewController(coordinator: self, target: target, onPosted: onPosted))
        compose.overrideUserInterfaceStyle = .dark
        topViewController.present(compose, animated: true)
    }

    func showError(_ message: String) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        topViewController.present(alert, animated: true)
    }

    /// Upvotes the story, or undoes the upvote. Updates the UI straight away and rolls it back
    /// if HN refuses; asks to sign in first when needed.
    func toggleVote(_ story: Story) {
        guard session.isSignedIn else {
            showSignIn { [weak self] in self?.toggleVote(story) }
            return
        }
        let wasUpvoted = session.isUpvoted(story.id)
        session.setLocalVote(story.id, upvoted: !wasUpvoted)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()

        Task {
            do {
                try await session.vote(story.id, up: !wasUpvoted)
            } catch {
                session.setLocalVote(story.id, upvoted: wasUpvoted, counted: true)
                if case HNSession.VoteError.sessionExpired = error {
                    session.signOut()
                    showSignIn { [weak self] in self?.toggleVote(story) }
                } else {
                    showError(error.localizedDescription)
                }
            }
        }
    }

    func showSettings() {
        let settings = UINavigationController(rootViewController: SettingsViewController(coordinator: self))
        settings.overrideUserInterfaceStyle = .dark
        navigationController.present(settings, animated: true)
    }

    func showSavedStories(animated: Bool = true) {
        navigationController.popToRootViewController(animated: animated)
    }

    /// HN's New list, on top of the front page.
    func showNewStories() {
        guard navigationController.topViewController === frontPage else { return }
        navigationController.pushViewController(newList, animated: true)
    }

    /// lobste.rs's Hottest list, on top of the saved list like search.
    func showLobsters() {
        guard navigationController.topViewController === savedList else { return }
        navigationController.pushViewController(lobstersList, animated: true)
    }

    /// Story search, on top of the saved list (in the list column when the window is wide).
    func showSearch() {
        guard navigationController.topViewController === savedList else { return }
        navigationController.pushViewController(search, animated: true)
    }

    /// Story search for `query`, from wherever the app was.
    func showSearch(query: String) {
        search.loadViewIfNeeded()
        search.search(for: query)
        if navigationController.topViewController !== search {
            navigationController.setViewControllers([savedList, search], animated: navigationController.view.window != nil)
        }
    }

    func showFrontPage(animated: Bool = true) {
        if navigationController.viewControllers.contains(frontPage) {
            navigationController.popToViewController(frontPage, animated: animated)
        } else {
            navigationController.pushViewController(frontPage, animated: animated)
        }
    }

    func makeCommentsViewController(id: Int, story: Story?, preloaded: LoadedItem? = nil) -> UIViewController {
        itemCache.prefetch(id: id)
        if Lobsters.isLobsters(id) {
            return LobstersCommentsViewController(id: id, story: story, coordinator: self, preloaded: preloaded)
        }
        return CommentsViewController(id: id, story: story, coordinator: self, preloaded: preloaded)
    }

    func showComments(for story: Story, from origin: OpenedFrom = .list) {
        visitedStories.markCommentsSeen(story)
        showComments(id: story.id, story: story, from: origin)
    }

    func showComments(id: Int, from origin: OpenedFrom = .detail) {
        showComments(id: id, story: nil, from: origin)
    }

    private func showComments(id: Int, story: Story?, from origin: OpenedFrom) {
        push(from: origin, waitingFor: { [itemCache] in
            let loaded = try await itemCache.item(id: id)
            // A link to a comment opens its story; have that ready too.
            if let storyID = loaded.item.parentStoryID {
                _ = try await itemCache.item(id: storyID)
            }
            return loaded
        }) { [unowned self] loaded in
            // Comment links still go through the screen's own (now cached) load, which focuses the comment.
            makeCommentsViewController(id: id, story: story, preloaded: loaded?.item.parentStoryID == nil ? loaded : nil)
        }
    }

    private var isWaitingToPush = false

    /// Pushes a screen after waiting briefly for its data (usually already prefetched on touch
    /// down), so it slides in filled instead of showing a loading state for a moment. Gives up
    /// waiting after 150 ms; taps while waiting are ignored.
    private func push<T: Sendable>(
        from origin: OpenedFrom,
        waitingFor fetch: @escaping @Sendable () async throws -> T,
        make: @escaping (T?) -> UIViewController
    ) {
        guard !isWaitingToPush else { return }
        isWaitingToPush = true
        Task {
            let value = await Self.firstResult(within: .milliseconds(150), fetch)
            isWaitingToPush = false
            show(make(value), from: origin)
        }
    }

    /// Pushes a screen, or when the window is wide opens it in the side column.
    private func show(_ viewController: UIViewController, from origin: OpenedFrom) {
        if split.isSplit {
            split.showDetail(viewController, replacing: origin == .list)
        } else {
            navigationController.pushViewController(viewController, animated: true)
        }
    }

    /// `fetch`'s result if it arrives within `limit`, else nil (the fetch carries on, for the screen).
    private nonisolated static func firstResult<T: Sendable>(
        within limit: Duration,
        _ fetch: @escaping @Sendable () async throws -> T
    ) async -> T? {
        await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            let finish: @Sendable (T?) -> Void = { value in
                let first = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                if first { continuation.resume(returning: value) }
            }
            Task { finish(try? await fetch()) }
            Task {
                try? await Task.sleep(for: limit)
                finish(nil)
            }
        }
    }

    /// Opens HN item links in the app and everything else in an in-app browser (beside the
    /// list when the window is wide).
    /// - Parameter story: The story the link belongs to, if it's a story's link.
    func open(_ url: URL, story: Story? = nil, from origin: OpenedFrom = .detail) {
        // X links go through Nitter, once an instance that's up is found (usually checked already).
        if nitter.redirects(url) {
            Task { show(link: await nitter.resolve(url), story: story, from: origin) }
        } else {
            show(link: url, story: story, from: origin)
        }
    }

    private func show(link url: URL, story: Story?, from origin: OpenedFrom) {
        switch HackerNewsLink(url) {
        case .item(let id):
            showComments(id: id, from: origin)
        case .user(let username):
            showUser(username, from: origin)
        case nil where Lobsters.storyID(in: url) != nil:
            showComments(id: Lobsters.storyID(in: url)!, from: origin)
        case nil where split.isSplit || !settings.opensLinksInSafari:
            show(ArticleViewController(url: url, story: story, coordinator: self), from: origin)
        case nil:
            navigationController.present(makeBrowser(for: url), animated: true)
        }
    }

    func makeBrowser(for url: URL) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = settings.opensLinksInReaderMode
        let browser = SFSafariViewController(url: url, configuration: configuration)
        browser.preferredBarTintColor = Theme.Color.backgroundDark
        browser.preferredControlTintColor = .white
        browser.dismissButtonStyle = .done
        return browser
    }

    /// An HN user's page: karma, about, their stories and comments.
    func showUser(_ username: String, from origin: OpenedFrom = .detail) {
        push(from: origin, waitingFor: { [userCache] in try await userCache.firstPage(of: username) }) { [unowned self] first in
            UserViewController(username: username, coordinator: self, users: userCache, preloaded: first)
        }
    }

    func share(_ url: URL, from sourceView: UIView) {
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = sourceView
        navigationController.present(activity, animated: true)
    }

    // MARK: Context menu previews

    /// Preview for long-pressing a story: the linked page, or the comments for self posts.
    func makePreview(for story: Story) -> UIViewController {
        if let url = story.url.map(nitter.resolveNow) {
            split.isSplit || !settings.opensLinksInSafari
                ? ArticleViewController(url: url, story: story, coordinator: self)
                : makeBrowser(for: url)
        } else {
            makeCommentsViewController(id: story.id, story: story)
        }
    }

    /// Called when the user taps a context menu preview to open it fully.
    func commitPreview(_ viewController: UIViewController) {
        if viewController is SFSafariViewController {
            navigationController.present(viewController, animated: true)
        } else {
            show(viewController, from: .list)
        }
    }

    // MARK: Menus

    /// Long-pressing a link inside a comment or self post.
    func linkMenu(for url: URL, sourceView: UIView) -> UIMenu {
        let openTitle = HackerNewsLink(url) == nil ? "Open Link" : "Open in HakkerNeus"
        let open = UIAction(title: openTitle, image: UIImage(systemName: "arrow.up.right.square")) { [weak self] _ in
            self?.open(url)
        }
        let safari = UIAction(title: "Open in Safari", image: UIImage(systemName: "safari")) { _ in
            UIApplication.shared.open(url)
        }
        let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
            UIPasteboard.general.url = url
        }
        let share = UIAction(title: "Share", image: UIImage(systemName: "square.and.arrow.up")) { [weak self, weak sourceView] _ in
            guard let sourceView else { return }
            self?.share(url, from: sourceView)
        }
        return UIMenu(title: url.host() ?? url.absoluteString, children: [
            UIMenu(options: .displayInline, children: [open, safari]),
            UIMenu(options: .displayInline, children: [copy, share]),
        ])
    }

    func storyMenu(for story: Story, sourceView: UIView, includeComments: Bool) -> UIMenu {
        // Built as the menu opens; the author's page is one tap away.
        story.author.map(prefetchUser)
        // With the comments item the menu is on a list row; without it, on the comments screen.
        let origin: OpenedFrom = includeComments ? .list : .detail
        var open: [UIMenuElement] = []
        if includeComments {
            open.append(UIAction(
                title: "Comments",
                subtitle: story.commentCount == 1 ? "1 comment" : "\(story.commentCount) comments",
                image: UIImage(systemName: "bubble.left.and.bubble.right")
            ) { [weak self] _ in
                self?.showComments(for: story, from: origin)
            })
        }
        if let url = story.url {
            open.append(UIAction(title: "Open Link", subtitle: url.host(), image: UIImage(systemName: "safari")) { [weak self] _ in
                self?.visitedStories.markOpened(story)
                self?.open(url, story: story, from: origin)
            })
        }

        let isUpvoted = session.isUpvoted(story.id)
        let vote = UIAction(
            title: isUpvoted ? "Unvote" : "Upvote",
            image: UIImage(systemName: isUpvoted ? "arrow.uturn.down" : "arrow.up")
        ) { [weak self] _ in
            self?.toggleVote(story)
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
        // For link posts, the HN discussion is a different URL from the article.
        let copyComments = story.url == nil ? nil : UIAction(
            title: "Copy Comments Link", image: UIImage(systemName: "bubble.left.and.text.bubble.right")
        ) { _ in
            UIPasteboard.general.url = story.hackerNewsURL
        }

        var user: [UIMenuElement] = []
        if let author = story.author {
            user.append(UIAction(title: author, image: UIImage(systemName: "person")) { [weak self] _ in
                self?.showUser(author, from: origin)
            })
        }

        let sections: [[UIMenuElement]] = [open, [vote, save], [share, copy] + [copyComments].compactMap { $0 }, user]
        return UIMenu(children: sections.filter { !$0.isEmpty }.map { UIMenu(options: .displayInline, children: $0) })
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
