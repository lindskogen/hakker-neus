import CoreGraphics

/// Finds where the next-thread button should scroll to.
enum ThreadJump {
    /// The first top-level comment starting below the top of the screen, given each top-level
    /// comment's top edge. A couple of points of slack so the thread already at the top doesn't count.
    static func next(after visibleTop: CGFloat, threadTops: [(id: Int, top: CGFloat)]) -> Int? {
        threadTops
            .sorted { $0.top < $1.top }
            .first { $0.top > visibleTop + 2 }?
            .id
    }
}
