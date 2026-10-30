import UIKit

/// Writing a comment on a story or a reply to a comment. Plain text with HN's formatting rules.
/// Dismissing keeps the draft for next time; so does a rejection from HN.
final class ComposeViewController: UIViewController, UITextViewDelegate {
    struct Target {
        /// The story or comment being replied to.
        let parentID: Int
        let storyID: Int
        /// Shown above the text: the story title, or the parent comment's author and opening words.
        let context: String
    }

    private unowned let coordinator: AppCoordinator
    private let target: Target
    private let onPosted: (Comment) -> Void
    private let textView = UITextView()
    private let spinner = UIActivityIndicatorView(style: .medium)
    private var postButton: UIBarButtonItem!

    init(coordinator: AppCoordinator, target: Target, onPosted: @escaping (Comment) -> Void) {
        self.coordinator = coordinator
        self.target = target
        self.onPosted = onPosted
        super.init(nibName: nil, bundle: nil)
        title = target.parentID == target.storyID ? "Comment" : "Reply"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.backgroundDark

        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.saveDraft()
            self?.dismiss(animated: true)
        })
        postButton = UIBarButtonItem(title: "Post", primaryAction: UIAction { [weak self] _ in self?.post() })
        postButton.style = .done
        postButton.accessibilityIdentifier = "compose.post"
        navigationItem.rightBarButtonItem = postButton

        let context = UILabel()
        context.text = target.context
        context.font = Theme.Font.body(size: 14, style: .subheadline)
        context.adjustsFontForContentSizeCategory = true
        context.textColor = UIColor.white.withAlphaComponent(0.6)
        context.numberOfLines = 3

        let hint = UILabel()
        hint.text = "Blank line for a new paragraph · *italic* · indent two spaces for code"
        hint.font = .preferredFont(forTextStyle: .caption1)
        hint.adjustsFontForContentSizeCategory = true
        hint.textColor = UIColor.white.withAlphaComponent(0.4)
        hint.numberOfLines = 0

        textView.font = Theme.Font.body()
        textView.adjustsFontForContentSizeCategory = true
        textView.textColor = .white
        textView.backgroundColor = UIColor.white.withAlphaComponent(0.06)
        textView.layer.cornerRadius = 10
        textView.textContainerInset = UIEdgeInsets(top: 10, left: 6, bottom: 10, right: 6)
        textView.text = coordinator.drafts[target.parentID]
        textView.delegate = self
        textView.accessibilityIdentifier = "compose.text"
        textView.accessibilityLabel = title

        let stack = UIStackView(arrangedSubviews: [context, hint, textView])
        stack.axis = .vertical
        stack.spacing = Theme.padding
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: Theme.padding),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor, constant: -Theme.padding),
        ])
        updatePostButton()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        textView.becomeFirstResponder()
    }

    func textViewDidChange(_ textView: UITextView) {
        updatePostButton()
    }

    private var trimmedText: String {
        textView.text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updatePostButton() {
        postButton.isEnabled = !trimmedText.isEmpty && !spinner.isAnimating
    }

    private func saveDraft() {
        coordinator.drafts[target.parentID] = trimmedText.isEmpty ? nil : textView.text
    }

    private func post() {
        let text = textView.text ?? ""
        setBusy(true)
        Task {
            defer { setBusy(false) }
            do {
                let session = coordinator.session
                let newID = try await session.postComment(parent: target.parentID, story: target.storyID, text: text)
                coordinator.drafts[target.parentID] = nil
                let comment = Comment(
                    // Until Algolia catches up, a local stand-in; negative so it can't clash with HN IDs.
                    id: newID ?? -Int(Date().timeIntervalSince1970 * 1000),
                    author: session.username,
                    text: HNFormatting.html(fromPlainText: text),
                    time: Date(),
                    children: []
                )
                let onPosted = onPosted
                dismiss(animated: true) { onPosted(comment) }
            } catch {
                saveDraft()
                if case HNSession.VoteError.sessionExpired = error {
                    coordinator.session.signOut()
                }
                let alert = UIAlertController(title: "Couldn't Post", message: error.localizedDescription, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                present(alert, animated: true)
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        busy ? spinner.startAnimating() : spinner.stopAnimating()
        navigationItem.rightBarButtonItem = busy ? UIBarButtonItem(customView: spinner) : postButton
        textView.isEditable = !busy
        updatePostButton()
    }
}
