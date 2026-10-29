import Foundation

/// The official HN API: https://github.com/HackerNews/API
struct FirebaseAPI: Sendable {
    let transport: HTTPTransport
    var baseURL = URL(string: "https://hacker-news.firebaseio.com/v0/")!

    func topStoryIDs() async throws -> [Int] {
        let data = try await transport.data(from: baseURL.appending(path: "topstories.json"))
        return try JSONDecoder().decode([Int].self, from: data)
    }

    /// Nil for deleted, dead or nonexistent items (the API returns `null` for the latter).
    func story(id: Int) async throws -> Story? {
        let data = try await transport.data(from: baseURL.appending(path: "item/\(id).json"))
        return try JSONDecoder().decode(Item?.self, from: data)?.story
    }

    struct Item: Decodable {
        let id: Int
        let type: String?
        let by: String?
        let title: String?
        let url: String?
        let text: String?
        let score: Int?
        let descendants: Int?
        let time: Int
        let deleted: Bool?
        let dead: Bool?

        var story: Story? {
            guard deleted != true, dead != true, let title else { return nil }
            return Story(
                id: id,
                title: title,
                author: by,
                url: url.flatMap(URL.init(string:)),
                text: text,
                score: score ?? 0,
                commentCount: descendants ?? 0,
                time: Date(timeIntervalSince1970: TimeInterval(time))
            )
        }
    }
}
