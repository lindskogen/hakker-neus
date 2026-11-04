import Foundation

/// lobste.rs items in the app's HN-shaped models. Lobsters identifies stories and comments by
/// short base-36 codes ("cozhtg"); the app keys everything by `Int`, so they become negative
/// numbers, which can't clash with HN's positive IDs.
enum Lobsters {
    static let baseURL = URL(string: "https://lobste.rs/")!

    static func isLobsters(_ id: Int) -> Bool { id < 0 }

    /// The app's ID for a short ID; nil if it isn't base 36.
    static func id(shortID: String) -> Int? {
        Int(shortID.lowercased(), radix: 36).map { -$0 }
    }

    /// The short ID for one of the app's lobste.rs IDs.
    static func shortID(_ id: Int) -> String {
        let code = String(-id, radix: 36)
        return String(repeating: "0", count: max(0, 6 - code.count)) + code
    }

    static func storyURL(_ id: Int) -> URL { baseURL.appending(path: "s/\(shortID(id))") }
    static func commentURL(_ id: Int) -> URL { baseURL.appending(path: "c/\(shortID(id))") }
    static func userURL(_ name: String) -> URL { baseURL.appending(path: "~\(name)") }

    /// The story ID in a lobste.rs story link (`https://lobste.rs/s/cozhtg/title`), if it is one.
    static func storyID(in url: URL) -> Int? {
        guard url.host()?.lowercased() == "lobste.rs" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "s" else { return nil }
        return id(shortID: parts[1])
    }
}

extension Story {
    var isLobsters: Bool { Lobsters.isLobsters(id) }
}

extension Comment {
    var isLobsters: Bool { Lobsters.isLobsters(id) }
}
