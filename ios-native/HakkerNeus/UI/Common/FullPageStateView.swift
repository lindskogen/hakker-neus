import UIKit

/// Centered loading, empty and error states (`FullPageView`, `ErrorView`, `EmptyCommentsView`).
final class FullPageStateView: UIView {
    enum State {
        case loading
        case message(systemImage: String, text: String)
        case error(Error)

        static let noComments = State.message(systemImage: "bubble.left", text: "No comments here")
    }

    private let spinner = UIActivityIndicatorView(style: .large)
    private let imageView = UIImageView()
    private let label = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)

        spinner.color = .white
        spinner.hidesWhenStopped = true

        imageView.preferredSymbolConfiguration = .init(pointSize: 60, weight: .regular)
        imageView.contentMode = .scaleAspectFit

        label.font = Theme.Font.light(size: 24)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = UIColor.white.withAlphaComponent(0.3)
        label.numberOfLines = 0
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [spinner, imageView, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = Theme.padding
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: Theme.padding * 2),
            stack.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: Theme.padding * 2),
        ])
        update()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var state: State = .loading {
        didSet { update() }
    }

    private func update() {
        switch state {
        case .loading:
            spinner.startAnimating()
            imageView.isHidden = true
            label.isHidden = true
        case .message(let systemImage, let text):
            spinner.stopAnimating()
            imageView.isHidden = false
            imageView.image = UIImage(systemName: systemImage)
            imageView.tintColor = UIColor.white.withAlphaComponent(0.3)
            label.isHidden = false
            label.text = text
        case .error(let error):
            spinner.stopAnimating()
            imageView.isHidden = false
            imageView.image = UIImage(systemName: "xmark.octagon")
            imageView.tintColor = Theme.Color.backgroundRed.withAlphaComponent(0.5)
            label.isHidden = false
            label.text = error.localizedDescription
        }
    }
}
