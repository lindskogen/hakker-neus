import Testing
@testable import HakkerNeus

struct CommentFlatteningTests {
    @Test func flattensDepthFirst() {
        let tree: [HNComment] = [
            .stub(1, [
                .stub(2, [.stub(3)]),
                .stub(4),
            ]),
            .stub(5),
        ]

        let flat = tree.flattened()

        #expect(flat.map(\.id) == [1, 2, 3, 4, 5])
        #expect(flat.map(\.depth) == [0, 1, 2, 1, 0])
    }

    @Test func skipsDeletedCommentsButKeepsTheirReplies() {
        let tree: [HNComment] = [
            .stub(1, text: nil, [
                .stub(2, [.stub(3)]),
            ]),
            .stub(4, text: "", []),
        ]

        let flat = tree.flattened()

        #expect(flat.map(\.id) == [2, 3])
        // Replies keep their original depth under the removed parent.
        #expect(flat.map(\.depth) == [1, 2])
    }

    @Test func emptyTree() {
        #expect([HNComment]().flattened().isEmpty)
    }
}
