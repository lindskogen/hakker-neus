import Foundation

/// The signed-in Hacker News session. HN has no write API, so signing in means posting its
/// login form and keeping the `user` cookie it sets; write actions later send that cookie.
/// Only the cookie is stored (in the Keychain), never the password.
@MainActor
final class HNSession {
    /// Posted when someone signs in or out.
    static let didChange = Notification.Name("HNSession.didChange")
    /// Posted when a story's vote changes. `object` is the story ID as an `Int`.
    static let votesChanged = Notification.Name("HNSession.votesChanged")

    enum VoteError: LocalizedError {
        case sessionExpired
        case noVoteLink
        case failed

        var errorDescription: String? {
            switch self {
            case .sessionExpired: "Your Hacker News session has expired. Sign in again."
            case .noVoteLink: "Hacker News doesn't allow voting on this right now."
            case .failed: "The vote didn't go through. Try again."
            }
        }
    }

    struct VoteState: Equatable {
        var isUpvoted: Bool
        /// HN only allows undoing a vote for a while.
        var canUnvote: Bool
    }

    enum SignInError: LocalizedError, Equatable {
        case badLogin
        /// HN wants a CAPTCHA, which it does after repeated failures.
        case captcha
        case unexpectedResponse

        var errorDescription: String? {
            switch self {
            case .badLogin: "Wrong username or password."
            case .captcha: "Hacker News wants to check you're human. Sign in on the website, then try again here."
            case .unexpectedResponse: "Hacker News didn't respond as expected. Try again later."
            }
        }
    }

    static let base = URL(string: "https://news.ycombinator.com/")!
    private static let cookieKey = "hn.userCookie"

    private let transport: SessionTransport
    private(set) var cookie: String?
    private let defaults: UserDefaults
    /// Stories the signed-in user has upvoted, as far as the app knows.
    private var upvoted: Set<Int>
    /// Votes cast since the story's score was loaded, which that score doesn't include yet.
    private var uncountedVotes: Set<Int> = []

    init(transport: SessionTransport = NoRedirectTransport(), defaults: UserDefaults = .standard) {
        self.transport = transport
        self.defaults = defaults
        cookie = Keychain.string(for: Self.cookieKey)
        upvoted = Set(defaults.array(forKey: "hn.upvoted") as? [Int] ?? [])
    }

    /// The signed-in username, read from the cookie (`username&token`).
    var username: String? {
        cookie.flatMap { $0.split(separator: "&", maxSplits: 1).first.map(String.init) }
    }

    var isSignedIn: Bool { cookie != nil }

    func signIn(username: String, password: String) async throws {
        var request = URLRequest(url: Self.base.appending(path: "login"))
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formBody(["acct": username, "pw": password, "goto": "news"])

        let (data, response) = try await transport.send(request)
        // Success: a redirect that sets the `user` cookie. Failure: the login page again, with 200.
        if let value = Self.userCookie(in: response) {
            setCookie(value)
            return
        }
        let page = String(decoding: data, as: UTF8.self).lowercased()
        if page.contains("recaptcha") || page.contains("validation required") {
            throw SignInError.captcha
        }
        if page.contains("bad login") {
            throw SignInError.badLogin
        }
        throw SignInError.unexpectedResponse
    }

    func signOut() {
        upvoted = []
        uncountedVotes = []
        defaults.removeObject(forKey: "hn.upvoted")
        setCookie(nil)
    }

    // MARK: Voting

    func isUpvoted(_ id: Int) -> Bool { upvoted.contains(id) }

    /// The score to show: the loaded one, plus a vote cast since it was loaded.
    func displayedScore(for story: Story) -> Int {
        story.score + (uncountedVotes.contains(story.id) ? 1 : 0)
    }

    /// Records a vote locally (for optimistic UI and rollback).
    func setLocalVote(_ id: Int, upvoted isUp: Bool, counted: Bool = false) {
        if isUp { upvoted.insert(id) } else { upvoted.remove(id) }
        if isUp && !counted { uncountedVotes.insert(id) } else { uncountedVotes.remove(id) }
        defaults.set(Array(upvoted), forKey: "hn.upvoted")
        NotificationCenter.default.post(name: Self.votesChanged, object: id)
    }

    /// Whether the user has voted on an item, read from its HN page.
    func voteState(for id: Int) async throws -> VoteState {
        Self.voteState(for: id, in: try await itemPage(id))
    }

    /// Upvotes, or undoes an upvote, using the per-session link on the item's page.
    func vote(_ id: Int, up: Bool) async throws {
        let page = try await itemPage(id)
        guard let path = Self.voteLink(for: id, how: up ? "up" : "un", in: page),
              let url = URL(string: path, relativeTo: Self.base)
        else { throw VoteError.noVoteLink }

        var request = URLRequest(url: url)
        authorize(&request)
        let (_, response) = try await transport.send(request)
        // Success redirects back to the item; an expired session redirects to the login page.
        let location = response.value(forHTTPHeaderField: "Location") ?? ""
        if location.contains("login") { throw VoteError.sessionExpired }
        guard (300..<400).contains(response.statusCode) else { throw VoteError.failed }
    }

    private func itemPage(_ id: Int) async throws -> String {
        var components = URLComponents(url: Self.base.appending(path: "item"), resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "id", value: String(id))]
        var request = URLRequest(url: components.url!)
        authorize(&request)
        let (data, response) = try await transport.send(request)
        if (300..<400).contains(response.statusCode),
           response.value(forHTTPHeaderField: "Location")?.contains("login") == true {
            throw VoteError.sessionExpired
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// The `vote?id=…&how=…&auth=…` link for an item, with HTML entities decoded.
    /// Pages fetched without a session have no `auth` token, so there's no usable link.
    static func voteLink(for id: Int, how: String, in page: String) -> String? {
        let pattern = "href='(vote\\?id=\(id)&amp;how=\(how)&amp;auth=[^']+)'"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: page, range: NSRange(page.startIndex..., in: page)),
              let range = Range(match.range(at: 1), in: page)
        else { return nil }
        return HTMLText.decodeEntities(String(page[range]))
    }

    static func voteState(for id: Int, in page: String) -> VoteState {
        let canUnvote = voteLink(for: id, how: "un", in: page) != nil
        // A voted item's up arrow gets the "nosee" class, even once it can no longer be undone.
        let hiddenArrow = page.range(of: "id='up_\(id)'[^>]*nosee|nosee[^>]*id='up_\(id)'", options: .regularExpression) != nil
        return VoteState(isUpvoted: canUnvote || hiddenArrow, canUnvote: canUnvote)
    }

    /// Adds the session cookie to a request to news.ycombinator.com.
    func authorize(_ request: inout URLRequest) {
        if let cookie { request.setValue("user=\(cookie)", forHTTPHeaderField: "Cookie") }
    }

    private func setCookie(_ value: String?) {
        cookie = value
        if let value { Keychain.set(value, for: Self.cookieKey) } else { Keychain.remove(Self.cookieKey) }
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    static func userCookie(in response: HTTPURLResponse) -> String? {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { fields, pair in
            if let key = pair.key as? String, let value = pair.value as? String { fields[key] = value }
        }
        return HTTPCookie.cookies(withResponseHeaderFields: headers, for: base)
            .first { $0.name == "user" && !$0.value.isEmpty }?
            .value
    }

    /// `application/x-www-form-urlencoded`, escaping everything but unreserved characters
    /// (URLComponents leaves "+" alone, which servers read as a space).
    static func formBody(_ fields: KeyValuePairs<String, String>) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let pairs = fields.map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
        }
        return Data(pairs.joined(separator: "&").utf8)
    }
}

/// Sends a request and returns the raw response, so the login redirect and its cookie can be seen.
protocol SessionTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

/// A URLSession that doesn't follow redirects or store cookies itself.
/// `@unchecked Sendable`: `session` is only assigned once, in `init`.
final class NoRedirectTransport: NSObject, SessionTransport, URLSessionTaskDelegate, @unchecked Sendable {
    private var session: URLSession!

    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw HNSession.SignInError.unexpectedResponse }
        return (data, http)
    }

    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
