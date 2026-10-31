import Foundation

/// User pages' profiles and first pages of stories, so a user page can be fetched as soon as
/// a menu offering it opens. Later pages and comments go straight to the API.
struct UserCache: Sendable {
    let api: UserAPI
    private let users = RequestCache<String, HNUser>(limit: 30)
    private let firstStories = RequestCache<String, UserActivityPage<Story>>(limit: 30)

    init(api: UserAPI) {
        self.api = api
    }

    func user(_ name: String) async throws -> HNUser {
        try await users.value(for: name) { [api] in try await api.user(name) }
    }

    func stories(by name: String, page: Int) async throws -> UserActivityPage<Story> {
        guard page == 0 else { return try await api.stories(by: name, page: page) }
        return try await firstStories.value(for: name) { [api] in try await api.stories(by: name, page: 0) }
    }

    func comments(by name: String, page: Int) async throws -> UserActivityPage<UserComment> {
        try await api.comments(by: name, page: page)
    }

    func prefetch(_ name: String) {
        Task { _ = try? await user(name) }
        Task { _ = try? await stories(by: name, page: 0) }
    }
}
