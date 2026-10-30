import Foundation
import Testing
@testable import HakkerNeus

struct CSVTests {
    @Test func parsesQuotedFieldsWithCommasQuotesAndNewlines() {
        let text = "a,b,c\r\n1,\"x, y\",\"say \"\"hi\"\"\nthere\"\n\n2,,last"
        #expect(CSV.parse(text) == [
            ["a", "b", "c"],
            ["1", "x, y", "say \"hi\"\nthere"],
            ["2", "", "last"],
        ])
    }

    @Test func formatRoundTrips() {
        let rows = [["id", "text"], ["1", "plain"], ["2", "with, comma \"and\" quote\nand newline"]]
        #expect(CSV.parse(CSV.format(rows)) == rows)
    }

    @Test func readsHackerFeedBookmarks() throws {
        let text = """
        id,title,url,hn_url,domain,type,user,points,comments,posted_at,saved_at,text,image_url
        50224210,SpeedCrunch 1.1,https://www.speedcrunch.org/,https://news.ycombinator.com/item?id=50224210,speedcrunch.org,link,LordNibbler,168,38,2026-10-24T19:19:43+00:00,2026-10-25T14:06:24.564880+00:00,,https://www.speedcrunch.org/screen1.png
        7,"Ask HN: Commas, ""quotes""?",,https://news.ycombinator.com/item?id=7,,ask,pg,5,1,2026-10-01T00:00:00+00:00,2026-10-02T00:00:00.000001+00:00,"Line one
        line two",
        not-a-number,Broken,,,,,,,,,,,
        """
        let result = BookmarksCSV.read(text)

        #expect(result.skipped == 1)
        #expect(result.entries.count == 2)
        let first = try #require(result.entries.first)
        #expect(first.story.id == 50224210)
        #expect(first.story.author == "LordNibbler")
        #expect(first.story.score == 168)
        #expect(first.story.commentCount == 38)
        #expect(first.story.time == ISO8601DateFormatter().date(from: "2026-10-24T19:19:43Z"))
        #expect(abs(first.savedAt.timeIntervalSince1970 - 1792937184.56488) < 0.01)

        let ask = result.entries[1].story
        #expect(ask.title == "Ask HN: Commas, \"quotes\"?")
        #expect(ask.url == nil)
        #expect(ask.text == "Line one\nline two")
    }

    @Test func exportReadsBackTheSame() {
        let entries: [SavedStoriesStore.Entry] = [
            .init(story: .stub(id: 1, title: "A, \"quoted\" title"), savedAt: Date(timeIntervalSince1970: 1_800_000_000.123456)),
        ]
        let back = BookmarksCSV.read(BookmarksCSV.write(entries)).entries
        #expect(back.map(\.story.id) == [1])
        #expect(back.first?.story.title == "A, \"quoted\" title")
        #expect(abs((back.first?.savedAt.timeIntervalSince1970 ?? 0) - 1_800_000_000.123456) < 0.001)
    }
}
