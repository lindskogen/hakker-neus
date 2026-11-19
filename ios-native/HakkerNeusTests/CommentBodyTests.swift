import Foundation
import Testing
@testable import HakkerNeus

struct CommentBodyTests {
    private typealias Run = CommentBody.Run

    // MARK: Fixtures from the RN app's CommentsSink.tsx

    @Test func italicQuote() {
        let html = "&gt; <i>The metro is also super efficient, you can get everywhere &quot;intra muros&quot; in 30-40 minutes.</i><p>Yes.  Both times I was there visiting, we didn&#x27;t bother with even the buses.  The Metro was usually a short walk, and a short wait."

        #expect(CommentBody(html: html).blocks == [
            .paragraph([
                Run(text: "> "),
                Run(text: "The metro is also super efficient, you can get everywhere \"intra muros\" in 30-40 minutes.", isItalic: true),
            ]),
            .paragraph([
                Run(text: "Yes.  Both times I was there visiting, we didn't bother with even the buses.  The Metro was usually a short walk, and a short wait."),
            ]),
        ])
    }

    @Test func link() {
        let html = "&gt;&gt; they seem ... incompatible with such performance<p>Might answer your question [0]<p>[0] <a href=\"https:&#x2F;&#x2F;news.ycombinator.com&#x2F;item?id=2192629\" rel=\"nofollow\">https:&#x2F;&#x2F;news.ycombinator.com&#x2F;item?id=2192629</a>"
        let url = URL(string: "https://news.ycombinator.com/item?id=2192629")!

        #expect(CommentBody(html: html).blocks == [
            .paragraph([Run(text: ">> they seem ... incompatible with such performance")]),
            .paragraph([Run(text: "Might answer your question [0]")]),
            .paragraph([Run(text: "[0] "), Run(text: url.absoluteString, link: url)]),
        ])
    }

    @Test func codeBlocksLoseTheirIndent() {
        let html = """
        Actually, that&#x27;s right, forgot about that :P<p>The only remaining mystery then would be why they bothered encoding it like this:<p><pre><code>    0xxxxxxx
            110xxxxx  10xxxxxx
        </code></pre>
        ... when it could have been done much more simply:<p><pre><code>    0xxxxxxx
            11xxxxxx  11xxxxxx  ...  10xxxxxx
        </code></pre>
        """

        #expect(CommentBody(html: html).blocks == [
            .paragraph([Run(text: "Actually, that's right, forgot about that :P")]),
            .paragraph([Run(text: "The only remaining mystery then would be why they bothered encoding it like this:")]),
            .code("0xxxxxxx\n110xxxxx  10xxxxxx"),
            .paragraph([Run(text: "... when it could have been done much more simply:")]),
            .code("0xxxxxxx\n11xxxxxx  11xxxxxx  ...  10xxxxxx"),
        ])
    }

    @Test func multipleCodeBlocksKeepBlankLinesAndEntities() {
        let html = "Failed entirely to work on my first attempt with:<p><pre><code>    curl -XHEAD https:&#x2F;&#x2F;google.com\n</code></pre>\nIn that it does a GET request:<p><pre><code>    import requests\n    \n    response = requests.get(&#x27;https:&#x2F;&#x2F;google.com&#x2F;&#x27;)\n</code></pre>\nClever idea"

        #expect(CommentBody(html: html).blocks == [
            .paragraph([Run(text: "Failed entirely to work on my first attempt with:")]),
            .code("curl -XHEAD https://google.com"),
            .paragraph([Run(text: "In that it does a GET request:")]),
            .code("import requests\n\nresponse = requests.get('https://google.com/')"),
            .paragraph([Run(text: "Clever idea")]),
        ])
    }

    // MARK: Edge cases

    @Test func newlinesOutsideCodeAreSpaces() {
        // Seen in the wild: HN passes single newlines through as-is.
        #expect(CommentBody(html: "I have similar hardware.\nSpend the time").blocks == [
            .paragraph([Run(text: "I have similar hardware. Spend the time")]),
        ])
    }

    @Test func italicLinkAndUnknownTags() {
        let html = "<i>see <a href=\"https://example.com\">this</a></i> and <b>that</b></p>"
        let url = URL(string: "https://example.com")!

        #expect(CommentBody(html: html).blocks == [
            .paragraph([
                Run(text: "see ", isItalic: true),
                Run(text: "this", isItalic: true, link: url),
                Run(text: " and that"),
            ]),
        ])
    }

    @Test func malformedInputDoesNotCrash() {
        #expect(CommentBody(html: "").blocks.isEmpty)
        #expect(CommentBody(html: "<p><p>").blocks.isEmpty)
        #expect(CommentBody(html: "a < b").blocks == [.paragraph([Run(text: "a < b")])])
        #expect(CommentBody(html: "<pre><code>unterminated").blocks == [.code("unterminated")])
        #expect(CommentBody(html: "</i></a>text").blocks == [.paragraph([Run(text: "text")])])
    }

    // MARK: Markdown tables (same cases as the Android CommentBodyTest)

    private typealias Table = CommentBody.Table

    private func cells(_ texts: String...) -> [[Run]] {
        texts.map { $0.isEmpty ? [] : [Run(text: $0)] }
    }

    @Test func tableOnSingleNewlines() {
        let html = "Benchmarks:\n| Name | Time |\n|:-----|-----:|\n| foo  | 1.2s |\n| bar  | 10s  |\nSo foo wins.<p>Next"

        #expect(CommentBody(html: html).blocks == [
            .paragraph([Run(text: "Benchmarks:")]),
            .table(Table(alignments: [.leading, .trailing], header: cells("Name", "Time"), rows: [cells("foo", "1.2s"), cells("bar", "10s")])),
            .paragraph([Run(text: "So foo wins.")]),
            .paragraph([Run(text: "Next")]),
        ])
    }

    @Test func tableWithRowsInSeparateParagraphs() {
        let html = "Intro<p>a | b | c<p>--- | :-: | ---<p>1 | 2<p>4 | 5 | 6 | 7<p>Outro"

        #expect(CommentBody(html: html).blocks == [
            .paragraph([Run(text: "Intro")]),
            .table(Table(
                alignments: [.leading, .center, .leading],
                header: cells("a", "b", "c"),
                rows: [cells("1", "2", ""), cells("4", "5", "6")]
            )),
            .paragraph([Run(text: "Outro")]),
        ])
    }

    @Test func tableCellsKeepLinksItalicsAndEscapedPipes() {
        let html = #"| Site | Note |\n| --- | --- |\n| <a href="https://example.com">example</a> | <i>a \| b</i> |"#
            .replacingOccurrences(of: "\\n", with: "\n")
        guard case .table(let table) = CommentBody(html: html).blocks.first else {
            Issue.record("Expected a table")
            return
        }
        #expect(table.rows == [[
            [Run(text: "example", link: URL(string: "https://example.com")!)],
            [Run(text: "a | b", isItalic: true)],
        ]])
    }

    @Test func tableInCodeBlock() {
        let html = "<pre><code>  | x | y |\n  |---|---|\n  | 1 | 2 |\n</code></pre>"
        #expect(CommentBody(html: html).blocks == [
            .table(Table(alignments: [.leading, .leading], header: cells("x", "y"), rows: [cells("1", "2")])),
        ])
        // Code that only contains a table somewhere stays code.
        #expect(CommentBody(html: "<pre><code>let a = 1\n| x |\n|---|</code></pre>").blocks == [.code("let a = 1\n| x |\n|---|")])
    }

    @Test(arguments: ["a | b\nc | d", "a | b<p>---", "a | b\n--- | --- | ---", "| a |\n|:-:-|", "x || y"])
    func notTables(html: String) {
        #expect(!CommentBody(html: html).blocks.contains { if case .table = $0 { true } else { false } })
    }

    @Test func pipesWithoutTableStayText() {
        #expect(CommentBody(html: "a | b\nc | d").blocks == [.paragraph([Run(text: "a | b c | d")])])
    }

    @Test func tablePlainTextIsAlignedMarkdown() {
        let html = "Sizes<p>|Name|Size|Mid|\n|-|-:|:-:|\n|Alpha|12|x|\n|B|1234|yes|"
        #expect(CommentBody(html: html).plainText == """
        Sizes

        | Name  | Size | Mid |
        | ----- | ---: | :-: |
        | Alpha |   12 |  x  |
        | B     | 1234 | yes |
        """)
    }

    @Test func plainTextForCopying() {
        let body = CommentBody(html: "One <i>two</i><p><pre><code>    let x = 1</code></pre>")
        #expect(body.plainText == "One two\n\nlet x = 1")
    }
}
