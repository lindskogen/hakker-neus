#if DEBUG
import Foundation

/// Debug fixture for comment rendering, like `CommentsSink.tsx` in the RN app.
/// Launch with `-CommentsSink` to open it on top of the story list.
struct CommentsSinkClient: HNClient {
    static let launchArgument = "-CommentsSink"
    static let itemID = -1

    let base: HNClient

    func topStoryIDs() async throws -> [Int] {
        try await base.topStoryIDs()
    }

    func newStoryIDs() async throws -> [Int] {
        try await base.newStoryIDs()
    }

    func story(id: Int) async throws -> Story? {
        try await base.story(id: id)
    }

    func item(id: Int) async throws -> StoryWithComments {
        switch id {
        case Self.itemID:
            return Self.fixture
        case Self.selfPostID:
            return Self.selfPost
        default:
            // Like Algolia: a comment's own subtree, plus the story it belongs to.
            if let comment = Self.fixture.comments.flattened().first(where: { $0.id == id })?.comment {
                let asStory = Story(id: id, title: "", author: comment.author, url: nil, text: comment.text, score: 0, commentCount: 0, time: comment.time)
                return StoryWithComments(story: asStory, comments: comment.children, parentStoryID: Self.itemID)
            }
            return try await base.item(id: id)
        }
    }

    static let selfPostID = -2

    private static func comment(_ id: Int, _ text: String, _ children: [Comment] = []) -> Comment {
        Comment(id: id, author: id == -11 ? "op" : "user\(-id - 10)", text: text, time: Date(timeIntervalSinceNow: -3600), children: children)
    }

    static let selfPost = StoryWithComments(
        story: Story(
            id: selfPostID, title: "Ask HN: Self post sink", author: "asker", url: nil,
            text: "Is there a way to <i>test</i> this?<p>See <a href=\"https:&#x2F;&#x2F;example.com&#x2F;self\">the docs</a>.",
            score: 1, commentCount: 0, time: Date()
        ),
        comments: []
    )

    static let fixture = StoryWithComments(
        story: Story(
            id: itemID, title: "Comments sink", author: "op", url: URL(string: "https://example.com"),
            text: nil, score: 1, commentCount: 5, time: Date()
        ),
        comments: [
            comment(-11, "&gt; <i>The metro is also super efficient, you can get everywhere &quot;intra muros&quot; in 30-40 minutes.</i><p>Yes.  Both times I was there visiting, we didn&#x27;t bother with even the buses.", [
                comment(-12, "&gt;&gt; they seem ... incompatible with such performance<p>Might answer your question [0]<p>[0] <a href=\"https:&#x2F;&#x2F;news.ycombinator.com&#x2F;item?id=2192629\" rel=\"nofollow\">https:&#x2F;&#x2F;news.ycombinator.com&#x2F;item?id=2192629</a> and <a href=\"https:&#x2F;&#x2F;example.com\">an external link</a>. Also <a href=\"item?id=-14\">a reply below</a> and <a href=\"item?id=-2\">a self post</a>."),
            ]),
            comment(-13, "Actually, that&#x27;s right, forgot about that :P<p>The only remaining mystery then would be why they bothered encoding it like this:<p><pre><code>    0xxxxxxx\n    110xxxxx  10xxxxxx\n    1110xxxx  10xxxxxx  10xxxxxx\n    11110xxx  10xxxxxx  10xxxxxx  10xxxxxx\n</code></pre>\n... when it could have been done much more simply by putting the continuation bit in position 6.", [
                comment(-14, "Failed entirely to work on my first attempt with:<p><pre><code>    curl -XHEAD https:&#x2F;&#x2F;google.com --header &quot;Accept: application&#x2F;json&quot; --header &quot;User-Agent: a-very-long-user-agent-string-that-scrolls&quot;\n</code></pre>\nIn that it does a GET request:<p><pre><code>    import requests\n    \n    response = requests.get(&#x27;https:&#x2F;&#x2F;google.com&#x2F;&#x27;)\n</code></pre>\nClever idea, but my first totally valid example failed."),
            ]),
        ]
    )
}
#endif
