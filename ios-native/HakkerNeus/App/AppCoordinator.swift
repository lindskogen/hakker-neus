import UIKit

/// Owns app-wide dependencies and the root navigation stack.
@MainActor
final class AppCoordinator {
    private let window: UIWindow
    private let navigationController = NavigationController()

    let client: HNClient
    let itemCache: ItemCache
    let savedStories: SavedStoriesStore

    init(
        window: UIWindow,
        client: HNClient = LiveHNClient(),
        savedStories: SavedStoriesStore = SavedStoriesStore()
    ) {
        self.window = window
        self.client = client
        self.itemCache = ItemCache(client: client)
        self.savedStories = savedStories
    }

    func start() {
        // Placeholder until the story list lands in phase 2.
        let root = PlaceholderViewController(feed: TopStoriesFeed(client: client))
        navigationController.setViewControllers([root], animated: false)

        window.rootViewController = navigationController
        window.makeKeyAndVisible()
    }
}

/// Navigation controller with a hidden bar that keeps the interactive swipe-back gesture.
final class NavigationController: UINavigationController, UIGestureRecognizerDelegate {
    override func viewDidLoad() {
        super.viewDidLoad()
        setNavigationBarHidden(true, animated: false)
        view.backgroundColor = Theme.Color.backgroundDark
        interactivePopGestureRecognizer?.delegate = self
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
