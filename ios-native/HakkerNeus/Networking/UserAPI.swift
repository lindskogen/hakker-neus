import Foundation

/// An HN user's profile, from the official API.
struct HNUser: Hashable, Sendable {
    let id: String
    let karma: Int
    let created: Date
    /// HN's HTML; nil when empty.
    let about: String?
}

/// A comment as listed on a user's page: the comment and the story it's on.
struct UserComment: Hashable, Sendable, Identifiable {
    let id: Int
    let text: String
    let time: Date
    let storyID: Int?
    let storyTitle: String?
}

/// One page of a user's stories or comments, newest first.
struct UserActivityPage<Item: Sendable>: Sendable {
    let items: [Item]
    let hasMore: Bool
}

enum UserAPIError: Error, LocalizedError {
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .notFound(let name): "There's no user called \(name)."
        }
    }
}

/// User pages: the profile from Firebase, recent stories and comments from Algolia's search
/// (Firebase only lists item IDs, which would mean a request per item).
struct UserAPI: Sendable {
    let transport: HTTPTransport
    var firebaseURL = URL(string: "https://hacker-news.firebaseio.com/v0/")!
    var algoliaURL = URL(string: "https://hn.algolia.com/api/v1/")!
    var pageSize = 30

    func user(_ name: String) async throws -> HNUser {
        let data = try await transport.data(from: firebaseURL.appending(path: "user/\(name).json"))
        guard let user = try JSONDecoder().decode(User?.self, from: data) else { throw UserAPIError.notFound(name) }
        return HNUser(
            id: user.id,
            karma: user.karma ?? 0,
            created: Date(timeIntervalSince1970: TimeInterval(user.created)),
            about: user.about.flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    func stories(by name: String, page: Int) async throws -> UserActivityPage<Story> {
        let result = try await search(tag: "story", name: name, page: page)
        let stories = result.hits.compactMap { hit -> Story? in
            guard let id = Int(hit.objectID), let title = hit.title else { return nil }
            return Story(
                id: id,
                title: title,
                author: hit.author,
                url: hit.url.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                text: hit.storyText,
                score: hit.points ?? 0,
                commentCount: hit.numComments ?? 0,
                time: Date(timeIntervalSince1970: TimeInterval(hit.createdAtI))
            )
        }
        return UserActivityPage(items: stories, hasMore: result.page + 1 < result.nbPages)
    }

    func comments(by name: String, page: Int) async throws -> UserActivityPage<UserComment> {
        let result = try await search(tag: "comment", name: name, page: page)
        let comments = result.hits.compactMap { hit -> UserComment? in
            guard let id = Int(hit.objectID), let text = hit.commentText else { return nil }
            return UserComment(
                id: id,
                text: text,
                time: Date(timeIntervalSince1970: TimeInterval(hit.createdAtI)),
                storyID: hit.storyID,
                storyTitle: hit.storyTitle
            )
        }
        return UserActivityPage(items: comments, hasMore: result.page + 1 < result.nbPages)
    }

    private func search(tag: String, name: String, page: Int) async throws -> SearchResult {
        var components = URLComponents(url: algoliaURL.appending(path: "search_by_date"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "tags", value: "\(tag),author_\(name)"),
            URLQueryItem(name: "hitsPerPage", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page)),
        ]
        let data = try await transport.data(from: components.url!)
        return try JSONDecoder().decode(SearchResult.self, from: data)
    }

    private struct User: Decodable {
        let id: String
        let karma: Int?
        let created: Int
        let about: String?
    }

    private struct SearchResult: Decodable {
        let hits: [Hit]
        let page: Int
        let nbPages: Int
    }

    private struct Hit: Decodable {
        let objectID: String
        let author: String?
        let title: String?
        let url: String?
        let storyText: String?
        let commentText: String?
        let points: Int?
        let numComments: Int?
        let storyID: Int?
        let storyTitle: String?
        let createdAtI: Int

        enum CodingKeys: String, CodingKey {
            case objectID, author, title, url, points
            case storyText = "story_text"
            case commentText = "comment_text"
            case numComments = "num_comments"
            case storyID = "story_id"
            case storyTitle = "story_title"
            case createdAtI = "created_at_i"
        }
    }
}
