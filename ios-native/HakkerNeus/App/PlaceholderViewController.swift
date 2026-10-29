import UIKit

/// Temporary root screen: loads the first page of top stories to smoke-test the data layer.
/// Replaced by `StoryListViewController` in phase 2.
final class PlaceholderViewController: UIViewController {
    private let feed: TopStoriesFeed
    private let spinner = UIActivityIndicatorView(style: .large)
    private let label = UILabel()

    init(feed: TopStoriesFeed) {
        self.feed = feed
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundOrange

        spinner.color = .white
        spinner.startAnimating()

        label.font = Theme.Font.title(isPad: traitCollection.userInterfaceIdiom == .pad)
        label.textColor = .white
        label.numberOfLines = 0
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.spacing = Theme.padding * 2
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
        ])

        Task { await load() }
    }

    private func load() async {
        do {
            let stories = try await feed.reload()
            label.text = "Loaded \(stories.count) stories\n\n\(stories.first?.title ?? "")"
        } catch {
            label.text = "\(error.localizedDescription)"
        }
        spinner.stopAnimating()
    }
}
