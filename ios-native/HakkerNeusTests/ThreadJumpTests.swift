import CoreGraphics
import Testing
@testable import HakkerNeus

struct ThreadJumpTests {
    private let threads: [(id: Int, top: CGFloat)] = [(1, 100), (2, 600), (3, 1500)]

    @Test func jumpsToTheNextThreadBelowTheTop() {
        #expect(ThreadJump.next(after: 0, threadTops: threads) == 1)
        #expect(ThreadJump.next(after: 300, threadTops: threads) == 2)
    }

    @Test func skipsTheThreadAlreadyAtTheTop() {
        #expect(ThreadJump.next(after: 600, threadTops: threads) == 3)
        #expect(ThreadJump.next(after: 599, threadTops: threads) == 3)
    }

    @Test func nothingAfterTheLastThread() {
        #expect(ThreadJump.next(after: 1500, threadTops: threads) == nil)
    }
}
