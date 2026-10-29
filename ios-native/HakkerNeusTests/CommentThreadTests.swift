import Testing
@testable import HakkerNeus

struct CommentThreadTests {
    /// 1
    /// ├ 2
    /// │ └ 3
    /// └ 4
    /// 5
    private let comments: [FlatComment] = [
        HNComment.stub(1, [.stub(2, [.stub(3)]), .stub(4)]),
        HNComment.stub(5),
    ].flattened()

    @Test func countsRepliesAtAnyDepth() {
        let thread = CommentThread(comments: comments)
        #expect(thread.replyCounts[1] == 3)
        #expect(thread.replyCounts[2] == 1)
        #expect(thread.replyCounts[3] == nil)
        #expect(thread.replyCounts[5] == nil)
    }

    @Test func collapsingHidesRepliesButKeepsTheComment() {
        var thread = CommentThread(comments: comments)

        thread.toggle(2)
        #expect(thread.visible.map(\.id) == [1, 2, 4, 5])

        thread.toggle(1)
        #expect(thread.visible.map(\.id) == [1, 5])

        // Expanding the outer comment restores the inner one in its collapsed state.
        thread.toggle(1)
        #expect(thread.visible.map(\.id) == [1, 2, 4, 5])
    }

    @Test func collapsedStateSurvivesRefreshForCommentsThatStillExist() {
        var thread = CommentThread(comments: comments)
        thread.toggle(2)

        let refreshed = CommentThread(comments: comments, collapsed: thread.collapsed.union([99]))
        #expect(refreshed.collapsed == [2])
    }
}
