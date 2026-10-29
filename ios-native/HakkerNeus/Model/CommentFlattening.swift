import Foundation

extension Array where Element == Comment {
    /// Depth-first flattening of a comment tree, ported from `flattenComments` in `CommentsList.tsx`.
    ///
    /// Comments without text (deleted) are left out, but their replies are kept. Replies keep
    /// the depth they would have had under the missing parent, so the indentation stays put.
    func flattened(depth: Int = 0) -> [FlatComment] {
        flatMap { comment -> [FlatComment] in
            let replies = comment.children.flattened(depth: depth + 1)
            guard let text = comment.text, !text.isEmpty else { return replies }
            return [FlatComment(comment: comment, depth: depth)] + replies
        }
    }
}
