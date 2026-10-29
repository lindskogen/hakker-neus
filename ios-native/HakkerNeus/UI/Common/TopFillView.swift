import UIKit

/// Fills the area above a list's first row, so a coloured first row reaches up under the clock
/// at rest (and while pulling to refresh) instead of leaving a dark strip.
final class TopFillView: UIView {
    private static let height: CGFloat = 2000

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        autoresizingMask = [.flexibleWidth]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// Adds the fill behind the rows of `scrollView`.
    func install(in scrollView: UIScrollView) {
        frame = CGRect(x: 0, y: -Self.height, width: scrollView.bounds.width, height: Self.height)
        scrollView.insertSubview(self, at: 0)
    }

    /// The colour of the first row, or nil for none.
    var color: UIColor? {
        get { backgroundColor }
        set {
            backgroundColor = newValue
            isHidden = newValue == nil
        }
    }
}
