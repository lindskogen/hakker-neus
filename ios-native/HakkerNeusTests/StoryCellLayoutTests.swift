import Testing
import UIKit
@testable import HakkerNeus

/// Lays out real rows to catch labels getting squeezed or hidden.
@MainActor
struct StoryCellLayoutTests {
    private func layOut(domain: String, comments: Int, category: UIContentSizeCategory) -> StoryCell {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 400))
        window.traitOverrides.preferredContentSizeCategory = category
        let cell = StoryCell(frame: CGRect(x: 0, y: 0, width: 402, height: 300))
        window.addSubview(cell)
        let story = Story(
            id: 1, title: "We're releasing the weights of Mistral Large 4", author: "a",
            url: URL(string: "https://\(domain)"), text: nil, score: 1083, commentCount: comments, time: Date()
        )
        cell.configure(with: story, backgroundColor: .orange, isSaved: false)
        window.isHidden = false
        cell.layoutIfNeeded()
        return cell
    }

    nonisolated private static let cases: [(String, UIContentSizeCategory)] = [
        ("mistral.ai", .large),
        ("a-really-quite-long-subdomain.claremontreviewofbooks.com", .large),
        ("a-really-quite-long-subdomain.claremontreviewofbooks.com", .accessibilityLarge),
    ]

    @Test(arguments: cases)
    func scoreIsNeverSqueezed(domain: String, category: UIContentSizeCategory) {
        let cell = layOut(domain: domain, comments: 12, category: category)
        #expect(cell.scoreLabel.bounds.width >= cell.scoreLabel.intrinsicContentSize.width - 0.5)
    }

    @Test(arguments: cases)
    func swipedCommentCountFitsTheUncoveredGap(domain: String, category: UIContentSizeCategory) {
        let cell = layOut(domain: domain, comments: 1083, category: category)
        cell.apply(StorySwipe(translation: -StorySwipe.commentsThreshold))
        let gapStart = cell.contentView.bounds.width - StorySwipe.commentsThreshold
        #expect(cell.commentCountLabel.frame.minX >= gapStart)
    }
}
