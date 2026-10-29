import Foundation

/// HN Search by Algolia: https://hn.algolia.com/api
/// Used for comments because it returns a whole tree in one request.
struct AlgoliaAPI: Sendable {
    let transport: HTTPTransport
    var baseURL = URL(string: "https://hn.algolia.com/api/v1/")!

    func item(id: Int) async throws -> StoryWithComments {
        let data = try await transport.data(from: baseURL.appending(path: "items/\(id)"))
        return try JSONDecoder().decode(Item.self, from: data).storyWithComments
    }

    final class Item: Decodable {
        let id: Int
        let author: String?
        let title: String?
        let url: String?
        let text: String?
        let points: Int?
        let createdAtI: Int
        let children: [Item]

        enum CodingKeys: String, CodingKey {
            case id, author, title, url, text, points, children
            case createdAtI = "created_at_i"
        }

        var storyWithComments: StoryWithComments {
            let comments = children.map(\.comment)
            let story = Story(
                id: id,
                title: title ?? "",
                author: author,
                url: url.flatMap(URL.init(string:)),
                text: text,
                score: points ?? 0,
                // Algolia has no `descendants`; count the comments that have text instead.
                commentCount: comments.reduce(0) { $0 + $1.visibleCount },
                time: Date(timeIntervalSince1970: TimeInterval(createdAtI))
            )
            return StoryWithComments(story: story, comments: comments)
        }

        var comment: Comment {
            Comment(
                id: id,
                author: author,
                text: text,
                time: Date(timeIntervalSince1970: TimeInterval(createdAtI)),
                children: children.map(\.comment)
            )
        }
    }
}

private extension Comment {
    var visibleCount: Int {
        children.reduce(text == nil ? 0 : 1) { $0 + $1.visibleCount }
    }
}
