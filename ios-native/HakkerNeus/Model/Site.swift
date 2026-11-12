import Foundation

/// Which site the app is about: its feeds, colours and search. The saved list has both.
/// Switched by picking one of the other site's places in the sidebar.
enum Site: String, Codable, CaseIterable {
    case hackerNews
    case lobsters

    var name: String {
        switch self {
        case .hackerNews: "Hacker News"
        case .lobsters: "lobste.rs"
        }
    }

    var other: Site {
        switch self {
        case .hackerNews: .lobsters
        case .lobsters: .hackerNews
        }
    }
}
