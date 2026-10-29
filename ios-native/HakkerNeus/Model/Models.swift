import Foundation

/// A top-level HN item shown in the story list.
struct Story: Hashable, Sendable, Codable, Identifiable {
    let id: Int
    let title: String
    let author: String?
    let url: URL?
    /// Body HTML for self posts (Ask HN etc).
    let text: String?
    let score: Int
    let commentCount: Int
    let time: Date

    var hackerNewsURL: URL { .hackerNewsItem(id) }

    /// The linked site, e.g. "github.com", without a leading "www.". Nil for self posts.
    var displayDomain: String? {
        guard let host = url?.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}

/// A comment and its replies. `text` is HN's HTML and is nil for deleted comments.
struct Comment: Hashable, Sendable, Identifiable {
    let id: Int
    let author: String?
    let text: String?
    let time: Date
    let children: [Comment]

    var hackerNewsURL: URL { .hackerNewsItem(id) }
}

/// A comment placed in a flat list, with its nesting depth.
struct FlatComment: Hashable, Sendable, Identifiable {
    let comment: Comment
    let depth: Int

    var id: Int { comment.id }
}

/// An item together with its comment tree, as shown on the comments screen.
/// The item may itself be a comment when following an HN link to a comment.
struct StoryWithComments: Hashable, Sendable {
    let story: Story
    let comments: [Comment]
    /// Set when the item is a comment: the story it belongs to.
    var parentStoryID: Int?
}

extension URL {
    static func hackerNewsItem(_ id: Int) -> URL {
        URL(string: "https://news.ycombinator.com/item?id=\(id)")!
    }
}
