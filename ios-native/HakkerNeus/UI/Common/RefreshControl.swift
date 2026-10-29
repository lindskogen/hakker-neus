import UIKit

/// White pull-to-refresh with a haptic when it triggers.
///
/// Updating a collection view while it's pulled past the top, or still springing back from that,
/// makes the content snap into place. That happens whenever the data comes back quickly, so
/// `endRefreshing(applying:)` holds the update until the list has come to rest.
final class RefreshControl: UIRefreshControl {
    private let haptics = UIImpactFeedbackGenerator(style: .medium)
    private var waitingLink: CADisplayLink?
    private var pendingUpdate: (() -> Void)?

    override init() {
        super.init()
        tintColor = .white
        addTarget(self, action: #selector(didTrigger), for: .valueChanged)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc private func didTrigger() {
        haptics.impactOccurred()
    }

    /// Runs `update` and ends refreshing, now or as soon as the list has stopped moving.
    /// If called again while waiting, only the latest update runs.
    func endRefreshing(applying update: @escaping () -> Void) {
        pendingUpdate = update
        guard isSettled else {
            if waitingLink == nil {
                waitingLink = CADisplayLink(target: self, selector: #selector(checkSettled))
                waitingLink?.add(to: .main, forMode: .common)
            }
            return
        }
        finish()
    }

    override func endRefreshing() {
        endRefreshing(applying: {})
    }

    /// Not being dragged, and not springing back from a drag either.
    private var isSettled: Bool {
        guard let scrollView = superview as? UIScrollView else { return true }
        return !scrollView.isTracking && !scrollView.isDecelerating
    }

    @objc private func checkSettled() {
        if isSettled { finish() }
    }

    private func finish() {
        waitingLink?.invalidate()
        waitingLink = nil

        let update = pendingUpdate
        pendingUpdate = nil
        update?()
        super.endRefreshing()
    }
}
