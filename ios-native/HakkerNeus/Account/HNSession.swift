import Foundation

/// The signed-in Hacker News session. HN has no write API, so signing in means posting its
/// login form and keeping the `user` cookie it sets; write actions later send that cookie.
/// Only the cookie is stored (in the Keychain), never the password.
@MainActor
final class HNSession {
    /// Posted when someone signs in or out.
    static let didChange = Notification.Name("HNSession.didChange")

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

    init(transport: SessionTransport = NoRedirectTransport()) {
        self.transport = transport
        cookie = Keychain.string(for: Self.cookieKey)
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
        setCookie(nil)
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
