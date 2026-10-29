import Foundation
import Testing
@testable import HakkerNeus

struct RelativeTimeTests {
    private let now = Date(timeIntervalSince1970: 1_000_000_000)

    /// Expected strings match date-fns `formatDistanceStrict`.
    @Test(arguments: [
        (0, "0 seconds"),
        (1, "1 second"),
        (59, "59 seconds"),
        (60, "1 minute"),
        (90, "2 minutes"),
        (3600, "1 hour"),
        (5 * 3600, "5 hours"),
        (86400, "1 day"),
        (29 * 86400, "29 days"),
        (30 * 86400, "1 month"),
        (364 * 86400, "12 months"),
        (365 * 86400, "1 year"),
        (3 * 365 * 86400, "3 years"),
    ] as [(TimeInterval, String)])
    func formatsLikeDateFns(secondsAgo: TimeInterval, expected: String) {
        #expect(RelativeTime.string(from: now.addingTimeInterval(-secondsAgo), now: now) == expected)
    }
}

struct HTMLTextTests {
    @Test func decodesEntities() {
        #expect(HTMLText.decodeEntities("that&#x27;s &quot;it&quot; &amp; &#62; &gt;") == "that's \"it\" & > >")
        #expect(HTMLText.decodeEntities("https:&#x2F;&#x2F;example.com") == "https://example.com")
    }

    @Test func leavesStrayAmpersandsAlone() {
        #expect(HTMLText.decodeEntities("AT&T; R&D & more &bogus;") == "AT&T; R&D & more &bogus;")
    }
}

struct HackerNewsURLTests {
    @Test(arguments: [
        ("https://news.ycombinator.com/item?id=2192629", 2192629),
        ("http://news.ycombinator.com/item?id=1&p=2", 1),
    ])
    func recognizesItemLinks(url: String, id: Int) {
        #expect(URL(string: url)!.hackerNewsItemID == id)
    }

    @Test(arguments: [
        "https://news.ycombinator.com/user?id=pg",
        "https://news.ycombinator.com/item",
        "https://example.com/item?id=1",
        "https://notnews.ycombinator.com.evil.com/item?id=1",
    ])
    func ignoresOtherLinks(url: String) {
        #expect(URL(string: url)!.hackerNewsItemID == nil)
    }
}
