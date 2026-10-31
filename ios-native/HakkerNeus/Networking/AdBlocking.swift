import CryptoKit
import SafariServices
import WebKit

/// EasyList ad blocking. The rules live in the content blocker extension, which Safari uses for
/// the in-app Safari sheet once it's turned on in Settings; the article view in the iPad side
/// column compiles the same rules for its own web view.
@MainActor
enum AdBlocking {
    static let extensionIdentifier = "se.lindskogen.hakkerneues.ContentBlocker"

    /// The compiled rules, once ready.
    private(set) static var ruleList: WKContentRuleList?
    private static var loading: Task<WKContentRuleList?, Never>?

    /// Compiles the rules (or finds them compiled by an earlier launch). Compiling takes a few
    /// seconds, so it's started ahead of the first article.
    @discardableResult
    static func prepare() -> Task<WKContentRuleList?, Never> {
        if let loading { return loading }
        let task = Task { () -> WKContentRuleList? in
            let list = await load()
            ruleList = list
            return list
        }
        loading = task
        return task
    }

    private static func load() async -> WKContentRuleList? {
        guard let url = Bundle.main.builtInPlugInsURL?.appending(path: "ContentBlocker.appex/blockerList.json"),
              let (json, identifier) = await Task.detached(operation: { () -> (String, String)? in
                  guard let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) else { return nil }
                  let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
                  return (json, "easylist-\(digest)")
              }).value
        else { return nil }

        let store = WKContentRuleListStore.default()!
        if let compiled = try? await store.contentRuleList(forIdentifier: identifier) {
            return compiled
        }
        // A new list replaces the old ones.
        for old in await store.availableIdentifiers() ?? [] where old != identifier {
            try? await store.removeContentRuleList(forIdentifier: old)
        }
        do {
            return try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
        } catch {
            NSLog("Couldn't compile the ad blocking rules: %@", String(describing: error))
            return nil
        }
    }

    /// Whether the extension is turned on in Settings (for the Safari sheet).
    static func isExtensionEnabled() async -> Bool {
        await withCheckedContinuation { continuation in
            SFContentBlockerManager.getStateOfContentBlocker(withIdentifier: extensionIdentifier) { state, _ in
                continuation.resume(returning: state?.isEnabled ?? false)
            }
        }
    }
}
