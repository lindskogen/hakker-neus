import UIKit

/// Your profile, one of the sidebar's places: signed in, your Hacker News page (your stories
/// and comments); signed out, a way to sign in. Follows signing in and out.
final class ProfileViewController: UIViewController, StoryTransitionSource {
    private unowned let coordinator: AppCoordinator
    private var page: UserViewController?
    private let signedOut = FullPageStateView()
    private let signInButton = UIButton(type: .system)

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        title = "Profile"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark
        configureSignedOut()
        NotificationCenter.default.addObserver(forName: HNSession.didChange, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showCurrentUser() }
        }
        showCurrentUser()
    }

    private func configureSignedOut() {
        signedOut.state = .message(systemImage: "person.crop.circle", text: "Sign in to see your stories and comments")
        signedOut.frame = view.bounds
        signedOut.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(signedOut)

        var config = UIButton.Configuration.filled()
        config.title = "Sign In"
        config.baseBackgroundColor = Theme.Color.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(top: 12, leading: 28, bottom: 12, trailing: 28)
        signInButton.configuration = config
        signInButton.accessibilityIdentifier = "profile.signIn"
        signInButton.addAction(UIAction { [unowned self] _ in coordinator.showSignIn() }, for: .touchUpInside)
        signInButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(signInButton)
        NSLayoutConstraint.activate([
            signInButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            signInButton.topAnchor.constraint(equalTo: view.centerYAnchor, constant: 70),
        ])
    }

    /// Shows the signed-in user's page, or the way to sign in.
    private func showCurrentUser() {
        let username = coordinator.session.username
        guard page?.username != username else { return }

        if let page {
            page.willMove(toParent: nil)
            page.view.removeFromSuperview()
            page.removeFromParent()
            self.page = nil
        }
        signedOut.isHidden = username != nil
        signInButton.isHidden = username != nil
        guard let username else { return }

        let page = UserViewController(username: username, coordinator: coordinator, users: coordinator.userCache)
        addChild(page)
        page.view.frame = view.bounds
        page.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(page.view)
        page.didMove(toParent: self)
        self.page = page
        page.loadViewIfNeeded()
        // The corner button follows the new page's scrolling.
        if let navigation = navigationController as? NavigationController, navigation.topViewController === self {
            navigation.updateCornerButton(for: self, animated: true)
        }
    }

    func transitionViews(forStory id: Int) -> (card: UIView, title: UIView)? {
        page?.transitionViews(forStory: id)
    }
}

extension ProfileViewController: TopLevelScreen {
    var scrollView: UIScrollView? { page?.scrollView }
}
