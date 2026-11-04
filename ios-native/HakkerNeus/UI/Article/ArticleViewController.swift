import UIKit
import WebKit

/// A linked page, shown in the side column on wide screens (on the iPhone, links open in an
/// in-app Safari sheet instead, which can't be placed beside the list).
final class ArticleViewController: UIViewController {
    let url: URL
    /// The story the page belongs to, for the comments button.
    let story: Story?
    private unowned let coordinator: AppCoordinator

    private let webView: WKWebView = {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        return WKWebView(frame: .zero, configuration: configuration)
    }()
    private let bar = UIView()
    private let backButton = UIButton(type: .system)
    private let titleLabel = UILabel()
    private let progress = UIProgressView(progressViewStyle: .bar)
    private var observations: [NSKeyValueObservation] = []

    init(url: URL, story: Story?, coordinator: AppCoordinator) {
        self.url = url
        self.story = story
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark
        configureBar()

        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.allowsBackForwardNavigationGestures = false // The swipe goes back to the previous screen.
        // Pages in light mode: the app is always dark (and can't see the phone's setting), and
        // sites forced into dark mode switch to (or improvise) dark themes.
        webView.overrideUserInterfaceStyle = .light
        view.insertSubview(webView, belowSubview: bar)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: bar.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            webView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        observations = [
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.progressChanged(webView.estimatedProgress) }
            },
            webView.observe(\.title) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.showTitle(webView.title) }
            },
        ]
        showTitle(nil)
        if let rules = AdBlocking.ruleList {
            webView.configuration.userContentController.add(rules)
            webView.load(URLRequest(url: url))
        } else {
            // The first article after launch may come before the rules are compiled: wait briefly for them.
            Task {
                let rules = AdBlocking.prepare()
                let ready = await withTaskGroup(of: WKContentRuleList?.self) { group in
                    group.addTask { await rules.value }
                    group.addTask { try? await Task.sleep(for: .seconds(2)); return nil }
                    let first = await group.next() ?? nil
                    group.cancelAll()
                    return first
                }
                if let ready { webView.configuration.userContentController.add(ready) }
                webView.load(URLRequest(url: url))
            }
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // At the bottom of a stack (the iPhone layout after the window narrows) there's nothing to go back to.
        backButton.isHidden = navigationController?.viewControllers.first === self
    }

    private func configureBar() {
        bar.backgroundColor = Theme.Color.backgroundDark
        bar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar)

        backButton.setImage(UIImage(systemName: "chevron.backward", withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .semibold)), for: .normal)
        backButton.tintColor = .white
        backButton.accessibilityLabel = "Back"
        backButton.addAction(UIAction { [unowned self] _ in navigationController?.popViewController(animated: true) }, for: .touchUpInside)

        titleLabel.font = Theme.Font.medium(size: 15, style: .subheadline)
        titleLabel.adjustsFontForContentSizeCategory = true
        titleLabel.textColor = UIColor(white: 1, alpha: 0.8)
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        var trailing: [UIButton] = []
        if let story {
            trailing.append(barButton("bubble.left.and.bubble.right", label: "Comments") { [unowned self] in
                // Back to the comments if that's where the page was opened from.
                if let stack = navigationController?.viewControllers, let index = stack.firstIndex(of: self), index > 0,
                   (stack[index - 1] as? StoryTransitionDestination)?.transitionStoryID == story.id {
                    navigationController?.popViewController(animated: true)
                } else {
                    coordinator.showComments(for: story, from: .detail)
                }
            })
        }
        trailing.append(barButton("safari", label: "Open in Safari") { [unowned self] in
            UIApplication.shared.open(webView.url ?? url)
        })
        let share = barButton("square.and.arrow.up", label: "Share") {}
        share.addAction(UIAction { [unowned self, unowned share] _ in coordinator.share(webView.url ?? url, from: share) }, for: .touchUpInside)
        trailing.append(share)

        let row = UIStackView(arrangedSubviews: [backButton, titleLabel] + trailing)
        row.alignment = .center
        row.spacing = Theme.padding * 1.5
        row.setCustomSpacing(Theme.padding, after: backButton)
        row.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(row)

        progress.progressTintColor = Theme.Color.accent
        progress.trackTintColor = .clear
        progress.translatesAutoresizingMaskIntoConstraints = false
        bar.addSubview(progress)

        NSLayoutConstraint.activate([
            bar.topAnchor.constraint(equalTo: view.topAnchor),
            bar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            row.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            row.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: Theme.padding * 1.5),
            row.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -Theme.padding * 1.5),
            row.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            progress.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
            progress.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            progress.bottomAnchor.constraint(equalTo: bar.bottomAnchor),
            backButton.widthAnchor.constraint(equalToConstant: 32),
        ])
    }

    private func barButton(_ systemName: String, label: String, action: @escaping () -> Void) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemName, withConfiguration: UIImage.SymbolConfiguration(pointSize: 17, weight: .regular)), for: .normal)
        button.tintColor = .white
        button.accessibilityLabel = label
        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.widthAnchor.constraint(equalToConstant: 36).isActive = true
        return button
    }

    private func showTitle(_ title: String?) {
        titleLabel.text = title.flatMap { $0.isEmpty ? nil : $0 } ?? story?.title ?? url.host()
    }

    private func progressChanged(_ value: Double) {
        progress.setProgress(Float(value), animated: value > Double(progress.progress))
        let done = value >= 1
        UIView.animate(withDuration: 0.25, delay: done ? 0.2 : 0) { self.progress.alpha = done ? 0 : 1 }
    }
}
