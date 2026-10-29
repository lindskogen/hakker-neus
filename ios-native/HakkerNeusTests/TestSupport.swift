import Foundation
@testable import HakkerNeus

private final class BundleToken {}

enum Fixture {
    static func data(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        guard let url = bundle.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile, userInfo: [NSFilePathErrorKey: "\(name).json"])
        }
        return try Data(contentsOf: url)
    }
}

/// Serves canned responses keyed by URL path.
struct StubTransport: HTTPTransport {
    var responses: [String: Result<Data, HNClientError>]

    func data(from url: URL) async throws -> Data {
        guard let response = responses[url.path()] else { throw HNClientError.badStatus(404) }
        return try response.get()
    }
}

/// In-memory `HNClient` that counts requests.
actor StubClient: HNClient {
    var ids: [Int]
    var stories: [Int: Story]
    var items: [Int: StoryWithComments] = [:]
    var failingItems: Set<Int> = []

    private(set) var storyRequests: [Int] = []
    private(set) var itemRequests: [Int] = []
    private(set) var idRequests = 0

    init(ids: [Int], stories: [Int: Story] = [:]) {
        self.ids = ids
        self.stories = stories
    }

    static func withStories(_ ids: [Int]) -> StubClient {
        StubClient(ids: ids, stories: Dictionary(uniqueKeysWithValues: ids.map { ($0, .stub(id: $0)) }))
    }

    func setIDs(_ ids: [Int]) { self.ids = ids }
    func setItem(_ item: StoryWithComments, id: Int) { items[id] = item }
    func setFailing(_ id: Int, _ failing: Bool) {
        if failing { failingItems.insert(id) } else { failingItems.remove(id) }
    }

    func topStoryIDs() async throws -> [Int] {
        idRequests += 1
        return ids
    }

    func story(id: Int) async throws -> Story? {
        storyRequests.append(id)
        await Task.yield()
        return stories[id]
    }

    func item(id: Int) async throws -> StoryWithComments {
        itemRequests.append(id)
        await Task.yield()
        if failingItems.contains(id) { throw HNClientError.badStatus(500) }
        guard let item = items[id] else { throw HNClientError.notFound(id: id) }
        return item
    }
}

extension Story {
    static func stub(id: Int, title: String? = nil) -> Story {
        Story(
            id: id,
            title: title ?? "Story \(id)",
            author: "author",
            url: URL(string: "https://example.com/\(id)"),
            text: nil,
            score: 1,
            commentCount: 0,
            time: Date(timeIntervalSince1970: TimeInterval(id))
        )
    }
}

extension Comment {
    static func stub(_ id: Int, text: String? = "text", _ children: [Comment] = []) -> Comment {
        Comment(id: id, author: "user\(id)", text: text, time: Date(timeIntervalSince1970: 0), children: children)
    }
}

/// Swift Testing also declares a `Comment` type, so tests refer to the model by this name.
typealias HNComment = HakkerNeus.Comment
