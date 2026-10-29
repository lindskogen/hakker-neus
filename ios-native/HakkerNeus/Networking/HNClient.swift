import Foundation

protocol HNClient: Sendable {
    /// IDs of the current front page, in rank order (up to 500).
    func topStoryIDs() async throws -> [Int]

    /// A single story, or nil if it is deleted, dead or missing.
    func story(id: Int) async throws -> Story?

    /// An item with its full comment tree.
    func item(id: Int) async throws -> StoryWithComments
}

enum HNClientError: Error, LocalizedError, Equatable {
    case badStatus(Int)
    case notFound(id: Int)

    var errorDescription: String? {
        switch self {
        case .badStatus(let code): "The server responded with status \(code)."
        case .notFound(let id): "Item \(id) could not be found."
        }
    }
}

/// The only network primitive the clients need, so tests can serve fixtures.
protocol HTTPTransport: Sendable {
    func data(from url: URL) async throws -> Data
}

extension URLSession: HTTPTransport {
    func data(from url: URL) async throws -> Data {
        let (data, response) = try await data(from: url, delegate: nil)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw HNClientError.badStatus(http.statusCode)
        }
        return data
    }
}
