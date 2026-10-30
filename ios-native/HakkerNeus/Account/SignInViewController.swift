import SafariServices
import UIKit

/// Username and password for news.ycombinator.com. Works with Password AutoFill.
final class SignInViewController: UIViewController, UITextFieldDelegate {
    private unowned let coordinator: AppCoordinator
    /// Called after signing in, e.g. to carry out the vote that asked for it.
    var onSignedIn: (() -> Void)?
    private let usernameField = UITextField()
    private let passwordField = UITextField()
    private let signInButton = UIButton(type: .system)
    private let errorLabel = UILabel()
    private let websiteButton = UIButton(type: .system)
    private let spinner = UIActivityIndicatorView(style: .medium)

    init(coordinator: AppCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
        title = "Sign In"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(systemItem: .cancel, primaryAction: UIAction { [weak self] _ in
            self?.dismiss(animated: true)
        })

        let intro = UILabel()
        intro.text = "Sign in with your Hacker News account to vote and comment. Your password is sent to news.ycombinator.com and not stored."
        intro.font = .preferredFont(forTextStyle: .footnote)
        intro.textColor = .secondaryLabel
        intro.numberOfLines = 0

        configure(usernameField, placeholder: "Username", contentType: .username, id: "signin.username")
        usernameField.returnKeyType = .next
        configure(passwordField, placeholder: "Password", contentType: .password, id: "signin.password")
        passwordField.isSecureTextEntry = true
        passwordField.returnKeyType = .go

        var buttonConfig = UIButton.Configuration.filled()
        buttonConfig.title = "Sign In"
        buttonConfig.baseBackgroundColor = Theme.Color.accent
        buttonConfig.cornerStyle = .large
        signInButton.configuration = buttonConfig
        signInButton.accessibilityIdentifier = "signin.submit"
        signInButton.addAction(UIAction { [weak self] _ in self?.submit() }, for: .touchUpInside)

        errorLabel.font = .preferredFont(forTextStyle: .footnote)
        errorLabel.textColor = .systemRed
        errorLabel.numberOfLines = 0
        errorLabel.isHidden = true

        var websiteConfig = UIButton.Configuration.plain()
        websiteConfig.title = "Sign in on the website"
        websiteButton.configuration = websiteConfig
        websiteButton.isHidden = true
        websiteButton.addAction(UIAction { [weak self] _ in self?.openWebsite() }, for: .touchUpInside)

        spinner.hidesWhenStopped = true

        let stack = UIStackView(arrangedSubviews: [intro, usernameField, passwordField, signInButton, spinner, errorLabel, websiteButton])
        stack.axis = .vertical
        stack.spacing = 12
        stack.setCustomSpacing(20, after: intro)
        stack.setCustomSpacing(20, after: passwordField)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 24),
            stack.leadingAnchor.constraint(equalTo: view.readableContentGuide.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.readableContentGuide.trailingAnchor),
            usernameField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            passwordField.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            signInButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48),
        ])
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        usernameField.becomeFirstResponder()
    }

    private func configure(_ field: UITextField, placeholder: String, contentType: UITextContentType, id: String) {
        field.placeholder = placeholder
        field.textContentType = contentType
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.borderStyle = .none
        field.backgroundColor = .secondarySystemGroupedBackground
        field.layer.cornerRadius = 10
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 1))
        field.leftViewMode = .always
        field.adjustsFontForContentSizeCategory = true
        field.font = .preferredFont(forTextStyle: .body)
        field.accessibilityIdentifier = id
        field.delegate = self
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === usernameField {
            passwordField.becomeFirstResponder()
        } else {
            submit()
        }
        return true
    }

    private func submit() {
        let username = usernameField.text?.trimmingCharacters(in: .whitespaces) ?? ""
        let password = passwordField.text ?? ""
        guard !username.isEmpty, !password.isEmpty else {
            show(error: "Enter your username and password.")
            return
        }
        setBusy(true)
        Task {
            defer { setBusy(false) }
            do {
                try await coordinator.session.signIn(username: username, password: password)
                let onSignedIn = onSignedIn
                dismiss(animated: true) { onSignedIn?() }
            } catch let error as HNSession.SignInError {
                show(error: error.localizedDescription)
                websiteButton.isHidden = error != .captcha
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    private func setBusy(_ busy: Bool) {
        signInButton.isEnabled = !busy
        usernameField.isEnabled = !busy
        passwordField.isEnabled = !busy
        busy ? spinner.startAnimating() : spinner.stopAnimating()
        if busy { errorLabel.isHidden = true }
    }

    private func show(error: String) {
        errorLabel.text = error
        errorLabel.isHidden = false
        UIAccessibility.post(notification: .announcement, argument: error)
    }

    /// After a CAPTCHA, signing in once on the website usually clears it for the app too.
    private func openWebsite() {
        present(SFSafariViewController(url: HNSession.base.appending(path: "login")), animated: true)
    }
}
