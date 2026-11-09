import Foundation

/// Reading lobste.rs through its public JSON (no key): the Hottest list and each story with
/// its whole comment thread in one request. Items get the app's IDs (see `Lobsters`).
struct LobstersAPI: Sendable {
    let transport: HTTPTransport
    var baseURL = Lobsters.baseURL

    /// One page (25 stories) of the Hottest list; pages start at 1.
    func hottest(page: Int) async throws -> [Story] {
        try await stories(at: page == 1 ? "hottest.json" : "page/\(page).json")
    }

    /// One page (25 stories) of the Newest list, newest first; pages start at 1.
    func newest(page: Int) async throws -> [Story] {
        try await stories(at: page == 1 ? "newest.json" : "newest/page/\(page).json")
    }

    private func stories(at path: String) async throws -> [Story] {
        let data = try await transport.data(from: baseURL.appending(path: path))
        return try Self.decoder.decode([StoryJSON].self, from: data).compactMap(\.story)
    }

    func item(id: Int) async throws -> StoryWithComments {
        let data = try await transport.data(from: baseURL.appending(path: "s/\(Lobsters.shortID(id)).json"))
        let json = try Self.decoder.decode(StoryJSON.self, from: data)
        guard let story = json.story else { throw HNClientError.notFound(id: id) }
        return StoryWithComments(story: story, comments: Self.tree(json.comments ?? []))
    }

    /// Lobsters lists comments flat, in thread order, each naming its parent.
    static func tree(_ flat: [CommentJSON]) -> [Comment] {
        var children: [String?: [CommentJSON]] = [:]
        for comment in flat { children[comment.parentComment, default: []].append(comment) }
        func build(_ parent: String?) -> [Comment] {
            (children[parent] ?? []).compactMap { json in
                guard let id = Lobsters.id(shortID: json.shortID) else { return nil }
                return Comment(
                    id: id,
                    author: json.isDeleted == true ? nil : json.commentingUser,
                    text: json.isDeleted == true || json.isModerated == true ? nil : json.comment,
                    time: json.createdAt,
                    children: build(json.shortID)
                )
            }
        }
        return build(nil)
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        let without = Date.ISO8601FormatStyle()
        decoder.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            if let date = try? withFraction.parse(text) ?? without.parse(text) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unreadable date \(text)"))
        }
        return decoder
    }()

    struct StoryJSON: Decodable {
        let shortId: String
        let createdAt: Date
        let title: String
        let url: String?
        let score: Int
        let commentCount: Int
        let description: String?
        let submitterUser: String?
        let comments: [CommentJSON]?

        var story: Story? {
            guard let id = Lobsters.id(shortID: shortId) else { return nil }
            return Story(
                id: id,
                title: title,
                author: submitterUser,
                url: url.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                text: description.flatMap { $0.isEmpty ? nil : $0 },
                score: score,
                commentCount: commentCount,
                time: createdAt
            )
        }
    }

    struct CommentJSON: Decodable {
        let shortId: String
        let createdAt: Date
        let isDeleted: Bool?
        let isModerated: Bool?
        let comment: String
        let parentComment: String?
        let commentingUser: String?

        var shortID: String { shortId }
    }
}

/// Sends lobste.rs items (negative IDs) to `LobstersAPI` and everything else to HN, so lists,
/// the comments screen, prefetching and offline copies work the same for both.
struct SourceRoutingClient: HNClient {
    let hn: HNClient
    let lobsters: LobstersAPI
    /// Stories from the Hottest list, so rows don't need a request each.
    private let known = KnownStories()

    init(hn: HNClient, lobsters: LobstersAPI = LobstersAPI(transport: URLSession.shared)) {
        self.hn = hn
        self.lobsters = lobsters
    }

    func topStoryIDs() async throws -> [Int] { try await hn.topStoryIDs() }
    func newStoryIDs() async throws -> [Int] { try await hn.newStoryIDs() }

    /// The first four pages of Hottest (100 stories), fetched together.
    func lobstersStoryIDs() async throws -> [Int] {
        try await firstPages { [lobsters] in try await lobsters.hottest(page: $0) }
    }

    /// The first four pages of Newest (100 stories), fetched together.
    func lobstersNewestStoryIDs() async throws -> [Int] {
        try await firstPages { [lobsters] in try await lobsters.newest(page: $0) }
    }

    private func firstPages(_ fetch: @escaping @Sendable (Int) async throws -> [Story]) async throws -> [Int] {
        let pages = try await withThrowingTaskGroup(of: (Int, [Story]).self) { group in
            for page in 1...4 { group.addTask { (page, try await fetch(page)) } }
            var pages: [Int: [Story]] = [:]
            for try await (page, stories) in group { pages[page] = stories }
            return pages
        }
        let stories = (1...4).flatMap { pages[$0] ?? [] }
        await known.add(stories)
        var seen = Set<Int>()
        return stories.map(\.id).filter { seen.insert($0).inserted }
    }

    func story(id: Int) async throws -> Story? {
        guard Lobsters.isLobsters(id) else { return try await hn.story(id: id) }
        if let story = await known.story(id) { return story }
        return try await lobsters.item(id: id).story
    }

    func item(id: Int) async throws -> StoryWithComments {
        Lobsters.isLobsters(id) ? try await lobsters.item(id: id) : try await hn.item(id: id)
    }

    private actor KnownStories {
        private var stories: [Int: Story] = [:]
        func add(_ new: [Story]) { for story in new { stories[story.id] = story } }
        func story(_ id: Int) -> Story? { stories[id] }
    }
}
