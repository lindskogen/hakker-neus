import UIKit
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

struct HackerNewsLinkTests {
    @Test(arguments: [
        ("https://news.ycombinator.com/item?id=2192629", HackerNewsLink.item(2192629)),
        ("http://news.ycombinator.com/item?id=1&p=2", .item(1)),
        ("https://ycombinator.com/item?id=5", .item(5)),
        ("https://news.ycombinator.com/user?id=pg", .user("pg")),
    ])
    func recognizesItemAndUserLinks(url: String, link: HackerNewsLink) {
        #expect(HackerNewsLink(URL(string: url)!) == link)
    }

    @Test(arguments: [
        "https://news.ycombinator.com/item",
        "https://news.ycombinator.com/item?id=abc",
        "https://news.ycombinator.com/newest",
        "https://example.com/item?id=1",
        "https://notnews.ycombinator.com.evil.com/item?id=1",
    ])
    func leavesOtherLinksToTheBrowser(url: String) {
        #expect(HackerNewsLink(URL(string: url)!) == nil)
    }

    @Test func relativeLinksInCommentsResolveAgainstHN() {
        let body = CommentBody(html: "see <a href=\"item?id=123\">this</a>")
        guard case .paragraph(let runs) = body.blocks.first else {
            Issue.record("Expected a paragraph")
            return
        }
        let url = try? #require(runs.last?.link)
        #expect(url?.absoluteString == "https://news.ycombinator.com/item?id=123")
        #expect(url.flatMap(HackerNewsLink.init) == .item(123))
    }
}

struct StoryDomainTests {
    private func story(url: String?) -> Story {
        Story(id: 1, title: "t", author: nil, url: url.flatMap(URL.init(string:)), text: nil, score: 0, commentCount: 0, time: Date())
    }

    @Test(arguments: [
        ("https://www.example.com/a/b", "example.com"),
        ("https://github.com/apple/swift", "github.com"),
        ("http://blog.example.co.uk", "blog.example.co.uk"),
        ("https://wwwexample.com", "wwwexample.com"),
    ])
    func showsHostWithoutWWW(url: String, domain: String) {
        #expect(story(url: url).displayDomain == domain)
    }

    @Test func selfPostsHaveNoDomain() {
        #expect(story(url: nil).displayDomain == nil)
    }
}

@MainActor
struct DynamicTypeTests {
    private func traits(_ category: UIContentSizeCategory) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: category)
    }

    @Test func defaultSizeMatchesTheRNApp() {
        #expect(Theme.Font.title(isPad: false, traits: traits(.large)).pointSize == 25)
        #expect(Theme.Font.body(traits: traits(.large)).pointSize == 16)
        #expect(Theme.Font.medium(size: 13, traits: traits(.large)).pointSize == 13)
    }

    @Test func scalesWithTheUsersTextSize() {
        let small = Theme.Font.body(traits: traits(.small)).pointSize
        let large = Theme.Font.body(traits: traits(.accessibilityExtraLarge)).pointSize
        #expect(small < 16)
        #expect(large > 30)
    }

    @Test func decorativeNumbersAreCapped() {
        #expect(Theme.Font.body(size: 30, style: .title1, maximum: 40, traits: traits(.accessibilityExtraExtraExtraLarge)).pointSize == 40)
    }
}
