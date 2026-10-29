import Foundation

/// The flattened comments of one item plus which ones the user has collapsed.
struct CommentThread {
    let comments: [FlatComment]
    private(set) var collapsed: Set<Int> = []

    /// Number of replies (at any depth) under each comment.
    let replyCounts: [Int: Int]

    init(comments: [FlatComment], collapsed: Set<Int> = []) {
        self.comments = comments
        self.replyCounts = Self.countReplies(comments)
        // Drop collapsed IDs that no longer exist, e.g. after a refresh.
        self.collapsed = collapsed.intersection(comments.map(\.id))
    }

    /// Comments to show: collapsed comments stay visible but their replies are hidden.
    var visible: [FlatComment] {
        var result: [FlatComment] = []
        var hideDeeperThan: Int?
        for comment in comments {
            if let depth = hideDeeperThan {
                if comment.depth > depth { continue }
                hideDeeperThan = nil
            }
            result.append(comment)
            if collapsed.contains(comment.id) {
                hideDeeperThan = comment.depth
            }
        }
        return result
    }

    func isCollapsed(_ id: Int) -> Bool {
        collapsed.contains(id)
    }

    mutating func toggle(_ id: Int) {
        if collapsed.remove(id) == nil {
            collapsed.insert(id)
        }
    }

    /// Replies are the following comments that are deeper than the comment itself.
    private static func countReplies(_ comments: [FlatComment]) -> [Int: Int] {
        var counts: [Int: Int] = [:]
        // Stack of ancestors still open at the current position.
        var open: [FlatComment] = []
        for comment in comments {
            while let last = open.last, last.depth >= comment.depth {
                open.removeLast()
            }
            for ancestor in open {
                counts[ancestor.id, default: 0] += 1
            }
            open.append(comment)
        }
        return counts
    }
}
