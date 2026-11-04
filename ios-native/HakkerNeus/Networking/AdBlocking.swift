import CryptoKit
import SafariServices
import WebKit

/// A blocking list the built-in browser uses (converted by `tools/update-blocking-lists.sh`).
/// All are on unless turned off in Settings.
enum BlockingList: String, CaseIterable, Sendable {
    case easylist, easyprivacy, cookies, social

    var title: String {
        switch self {
        case .easylist: "Ads"
        case .easyprivacy: "Trackers"
        case .cookies: "Cookie Banners"
        case .social: "Social Widgets"
        }
    }

    /// The list's name and authors, for the credit line.
    var source: String {
        switch self {
        case .easylist: "EasyList"
        case .easyprivacy: "EasyPrivacy"
        case .cookies: "Fanboy's Cookie Monster List"
        case .social: "Fanboy's Social Blocking List"
        }
    }

    /// EasyList is in the Safari content blocker extension, which uses it too; the rest are the app's.
    var fileURL: URL? {
        self == .easylist
            ? Bundle.main.builtInPlugInsURL?.appending(path: "ContentBlocker.appex/easylist.json")
            : Bundle.main.url(forResource: rawValue, withExtension: "json")
    }
}

/// Ad and tracker blocking. The built-in browser compiles each list switched on in Settings for
/// its web views. The Safari content blocker extension has EasyList only, for the in-app Safari
/// sheet once it's turned on in the Settings app.
@MainActor
enum AdBlocking {
    static let extensionIdentifier = "se.lindskogen.hakkerneues.ContentBlocker"
    private static let disabledKey = "disabledBlockingLists"
    private static var defaults: UserDefaults { .standard }

    /// The compiled rules of the lists that are on, once ready.
    private(set) static var ruleLists: [WKContentRuleList]?
    private static var loading: Task<[WKContentRuleList], Never>?
    /// Bumped when the lists change, so an earlier compile doesn't overwrite a later one.
    private static var generation = 0

    static var enabledLists: [BlockingList] {
        let disabled = Set(defaults.stringArray(forKey: disabledKey) ?? [])
        return BlockingList.allCases.filter { !disabled.contains($0.rawValue) }
    }

    static func isEnabled(_ list: BlockingList) -> Bool {
        enabledLists.contains(list)
    }

    /// Switches a list on or off, for the built-in browser's next pages.
    static func setEnabled(_ list: BlockingList, _ enabled: Bool) {
        var disabled = Set(defaults.stringArray(forKey: disabledKey) ?? [])
        if enabled { disabled.remove(list.rawValue) } else { disabled.insert(list.rawValue) }
        defaults.set(disabled.sorted(), forKey: disabledKey)
        loading = nil
        ruleLists = nil
        generation += 1
        prepare()
    }

    /// Compiles the rules (or finds them compiled by an earlier launch). Compiling takes a few
    /// seconds, so it's started ahead of the first article.
    @discardableResult
    static func prepare() -> Task<[WKContentRuleList], Never> {
        if let loading { return loading }
        let lists = enabledLists
        let generation = generation
        let task = Task { () -> [WKContentRuleList] in
            var compiled: [WKContentRuleList] = []
            var identifiers: Set<String> = []
            for list in BlockingList.allCases {
                guard let (json, identifier) = await source(for: list) else { continue }
                identifiers.insert(identifier)
                if lists.contains(list), let rules = await load(json, identifier: identifier) { compiled.append(rules) }
            }
            // Rules of earlier versions of the lists go.
            let store = WKContentRuleListStore.default()!
            for old in await store.availableIdentifiers() ?? [] where !identifiers.contains(old) {
                try? await store.removeContentRuleList(forIdentifier: old)
            }
            if generation == Self.generation { ruleLists = compiled }
            return compiled
        }
        loading = task
        return task
    }

    /// The list's JSON and an identifier that changes with its contents.
    private static func source(for list: BlockingList) async -> (String, String)? {
        guard let url = list.fileURL else { return nil }
        return await Task.detached { () -> (String, String)? in
            guard let data = try? Data(contentsOf: url), let json = String(data: data, encoding: .utf8) else { return nil }
            let digest = SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
            return (json, "\(list.rawValue)-\(digest)")
        }.value
    }

    private static func load(_ json: String, identifier: String) async -> WKContentRuleList? {
        let store = WKContentRuleListStore.default()!
        if let compiled = try? await store.contentRuleList(forIdentifier: identifier) {
            return compiled
        }
        do {
            return try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
        } catch {
            NSLog("Couldn't compile the blocking rules %@: %@", identifier, String(describing: error))
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
