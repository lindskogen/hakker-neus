import Foundation

/// Stories from the official Firebase API, comment trees from Algolia.
struct LiveHNClient: HNClient {
    private let firebase: FirebaseAPI
    private let algolia: AlgoliaAPI

    init(transport: HTTPTransport = URLSession.shared) {
        firebase = FirebaseAPI(transport: transport)
        algolia = AlgoliaAPI(transport: transport)
    }

    func topStoryIDs() async throws -> [Int] {
        try await firebase.topStoryIDs()
    }

    func newStoryIDs() async throws -> [Int] {
        try await firebase.newStoryIDs()
    }

    func story(id: Int) async throws -> Story? {
        try await firebase.story(id: id)
    }

    func item(id: Int) async throws -> StoryWithComments {
        do {
            return try await algolia.item(id: id)
        } catch HNClientError.badStatus(404) {
            throw HNClientError.notFound(id: id)
        }
    }
}
