import Foundation
import Testing
@testable import HakkerNeus

struct HNFormattingTests {
    @Test func paragraphsItalicsCodeAndLinks() {
        let text = "First *point* & more\n\n  let x = 1\n  let y = 2\n\nSee https://example.com/a."
        #expect(HNFormatting.html(fromPlainText: text) ==
            "First <i>point</i> &amp; more<pre><code>    let x = 1\n    let y = 2</code></pre><p>See <a href=\"https://example.com/a\">https://example.com/a</a>.")
    }

    @Test func roundTripsThroughTheCommentParser() {
        let body = CommentBody(html: HNFormatting.html(fromPlainText: "One\n\nTwo"))
        #expect(body.plainText == "One\n\nTwo")
    }
}

@MainActor
struct CommentFormTests {
    @Test func findsTheHmacField() {
        let page = #"<form action="comment" method="post"><input type="hidden" name="parent" value="42"><input type="hidden" name="hmac" value="abc123def"><textarea name="text"></textarea>"#
        #expect(HNSession.hiddenField("hmac", in: page) == "abc123def")
        #expect(HNSession.hiddenField("parent", in: page) == "42")
    }

    @Test func extractsRejectionMessages() {
        let page = "<html><body><table><tr><td>You're posting too fast. Please slow down. Thanks.</td></tr></table></body></html>"
        #expect(HNSession.message(in: page).hasPrefix("You're posting too fast"))
    }
}

@MainActor
struct LocalReplyMergeTests {
    private let thread: [HNComment] = [.stub(1, [.stub(2)]), .stub(3)]

    @Test func insertsRepliesFirstUnderTheirParent() {
        let reply = HNComment(id: -1, author: "me", text: "hi", time: Date(), children: [])
        let merged = CommentsViewController.merge([(parent: 1, comment: reply)], into: thread, storyID: 100)
        #expect(merged.flattened().map(\.id) == [1, -1, 2, 3])
    }

    @Test func storyCommentsGoOnTop() {
        let reply = HNComment(id: -1, author: "me", text: "hi", time: Date(), children: [])
        let merged = CommentsViewController.merge([(parent: 100, comment: reply)], into: thread, storyID: 100)
        #expect(merged.flattened().map(\.id) == [-1, 1, 2, 3])
    }

    @Test func dropsLocalCopiesOnceTheServerHasThem() {
        let local = HNComment(id: -1, author: "me", text: "hi there", time: Date(), children: [])
        let server = thread + [HNComment(id: 99, author: "me", text: "hi there", time: Date(), children: [])]
        let merged = CommentsViewController.merge([(parent: 100, comment: local)], into: server, storyID: 100)
        #expect(!merged.flattened().map(\.id).contains(-1))
    }
}
