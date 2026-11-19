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

    // MARK: ASCII grid tables (same cases as the Android CommentBodyTest)

    /// A comment from the wild: a psql-style grid indented into a code block.
    private let modelsTable = """
      +-------------------------------+--------------+--------+--------+----------+-------+
      |              Lab              |      XL      |   L    |   M+   |    M     | S/XS  |
      +-------------------------------+--------------+--------+--------+----------+-------+
      | Google (Gemini 4 Family #1)   |              | Argon  |        |          |       |
      | Google (Gemini 4 Family #2)   |              | Carbon | Neon   | Hydrogen |       |
      | Anthropic (Claude 5.2 Family) | Fable/Mythos |        |        |          |       |
      | Anthropic (Claude 5.5 Family) |              | Opus   |        | Sonnet   | Haiku |
      | OpenAI (GPT 6.2 Family)       | Astra        | Sol    |        |          |       |
      | OpenAI (GPT 6.1 Family)       |              |        |        | Terra    |       |
      | OpenAI (GPT 6 Family)         |              |        |        |          | Luna  |
      +-------------------------------+--------------+--------+--------+----------+-------+
    """

    @Test func gridTableInCodeBlock() throws {
        let html = "Edited: For formatting and from feedback<p>So if I am getting this right?<p><pre><code>\(modelsTable)\n</code></pre>"
        let blocks = CommentBody(html: html).blocks
        #expect(blocks.count == 3)
        #expect(blocks[1] == .paragraph([Run(text: "So if I am getting this right?")]))
        guard case .table(let table) = try #require(blocks.last) else {
            Issue.record("Expected a table")
            return
        }
        #expect(table.header == cells("Lab", "XL", "L", "M+", "M", "S/XS"))
        #expect(table.alignments == Array(repeating: .leading, count: 6))
        #expect(table.rows.count == 7)
        #expect(table.rows[3] == cells("Anthropic (Claude 5.5 Family)", "", "Opus", "", "Sonnet", "Haiku"))
        #expect(table.rows[6] == cells("OpenAI (GPT 6 Family)", "", "", "", "", "Luna"))
    }

    @Test func gridTableWithWrappedRowsAndRuleAlignment() {
        // Pandoc: a rule under every row, so rows wrap; colons in the header rule align.
        let grid = """
        +-------+-----------+------:+
        | Name  | Notes     | Size  |
        +=======+:=========:+======:+
        | Alpha | the first | 12    |
        |       | one       |       |
        +-------+-----------+-------+
        | B     | a | pipe  | 1234  |
        +-------+-----------+-------+
        """
        #expect(CommentBody(html: "<pre><code>\(grid)</code></pre>").blocks == [
            .table(Table(
                alignments: [.leading, .center, .trailing],
                header: cells("Name", "Notes", "Size"),
                rows: [cells("Alpha", "the first one", "12"), cells("B", "a | pipe", "1234")]
            )),
        ])
    }

    @Test func gridTableInTextInfersRightAlignment() {
        // Typed straight into the comment, one line per row; numbers pushed right.
        let html = "Results:\n+------+-------+\n| Name | Count |\n+------+-------+\n| foo  |     1 |\n| bar  |   200 |\n+------+-------+\nThanks"
        #expect(CommentBody(html: html).blocks == [
            .paragraph([Run(text: "Results:")]),
            .table(Table(alignments: [.leading, .trailing], header: cells("Name", "Count"), rows: [cells("foo", "1"), cells("bar", "200")])),
            .paragraph([Run(text: "Thanks")]),
        ])
    }

    @Test(arguments: ["+---+", "<pre><code>+--+--+\nnot a row\n+--+--+</code></pre>", "a +-+ b", "+++\n| a |"])
    func notGridTables(html: String) {
        #expect(!CommentBody(html: html).blocks.contains { if case .table = $0 { true } else { false } })
    }

    @Test func plainTextForCopying() {
        let body = CommentBody(html: "One <i>two</i><p><pre><code>    let x = 1</code></pre>")
        #expect(body.plainText == "One two\n\nlet x = 1")
    }
}
