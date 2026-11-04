import Foundation

/// Opens x.com and twitter.com links through Nitter, which shows posts without an X account:
/// xcancel.com first, then the user's fallbacks in order, skipping instances that are down
/// (they come and go, and get suspended). When none respond, links open on X.
@MainActor
final class NitterRedirect {
    static let primary = "xcancel.com"
    /// Offered as fallbacks. Checked 2026-11-04: most public instances shut down after X's
    /// cease-and-desist letters; these answer, behind bot checks a browser passes.
    static let suggestedFallbacks = ["nitter.tiekoetter.com", "nitter.meowing.monster", "nitter.privacyredirect.com"]
    private static let xHosts: Set<String> = ["x.com", "www.x.com", "mobile.x.com", "twitter.com", "www.twitter.com", "mobile.twitter.com"]
    /// How long a check of the instances is trusted.
    private static let checkLifetime: TimeInterval = 10 * 60

    private let settings: AppSettings
    private let session: URLSession
    private var lastCheck: (host: String?, at: Date)?
    private var checking: Task<String?, Never>?

    init(settings: AppSettings, session: URLSession = .shared) {
        self.settings = settings
        self.session = session
    }

    static func isXLink(_ url: URL) -> Bool {
        url.host().map { xHosts.contains($0.lowercased()) } ?? false
    }

    /// Whether `url` is an X link that should go through Nitter.
    func redirects(_ url: URL) -> Bool {
        settings.opensXLinksViaNitter && Self.isXLink(url)
    }

    /// The instances in the order they're tried.
    var instances: [String] { [Self.primary] + settings.nitterFallbacks }

    /// `url` on the first instance that's up; `url` itself if it isn't redirected or none is up.
    func resolve(_ url: URL) async -> URL {
        guard redirects(url), let host = await workingInstance() else { return url }
        return Self.url(url, on: host)
    }

    /// Like `resolve`, without waiting: uses the last check, else the primary.
    func resolveNow(_ url: URL) -> URL {
        guard redirects(url) else { return url }
        let host = lastCheck.map(\.host) ?? Self.primary
        return host.map { Self.url(url, on: $0) } ?? url
    }

    /// Checks the instances ahead of the first X link.
    func prepare() {
        guard settings.opensXLinksViaNitter else { return }
        Task { _ = await workingInstance() }
    }

    /// Forgets the last check, after the instances change.
    func invalidate() {
        lastCheck = nil
        checking = nil
    }

    private static func url(_ url: URL, on host: String) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = host
        components?.port = nil
        return components?.url ?? url
    }

    private func workingInstance() async -> String? {
        if let lastCheck, Date().timeIntervalSince(lastCheck.at) < Self.checkLifetime { return lastCheck.host }
        if let checking { return await checking.value }
        let instances = instances
        let session = session
        let task = Task<String?, Never> {
            for host in instances where await Self.isUp(host, session: session) { return host }
            return nil
        }
        checking = task
        let host = await task.value
        if checking == task {
            lastCheck = (host, Date())
            checking = nil
        }
        return host
    }

    /// Up unless it doesn't answer or answers like a suspended, overloaded or missing site
    /// (xcancel answers 451 while suspended). Bot checks (often 403) pass in a browser.
    private nonisolated static func isUp(_ host: String, session: URLSession) async -> Bool {
        guard let url = URL(string: "https://\(host)/") else { return false }
        var request = URLRequest(url: url, timeoutInterval: 3)
        request.httpMethod = "HEAD"
        guard let (_, response) = try? await session.data(for: request),
              let status = (response as? HTTPURLResponse)?.statusCode
        else { return false }
        return !(status == 404 || status == 429 || status == 451 || status >= 500)
    }
}
