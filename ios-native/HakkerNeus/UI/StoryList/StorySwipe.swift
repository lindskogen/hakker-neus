import CoreGraphics

/// Geometry of the story row swipe actions, ported from the `Swipeable` setup in `ListItem.tsx`.
/// Positive offsets drag the row right (save), negative offsets drag it left (comments).
struct StorySwipe: Equatable {
    enum Action: Equatable {
        case save
        case comments
    }

    /// Drag right this far to toggle saved.
    static let saveThreshold: CGFloat = 80
    /// Drag left this far to open the comments.
    static let commentsThreshold: CGFloat = 100

    /// How far the row has moved, after resistance.
    let offset: CGFloat

    /// The row follows the finger up to the threshold, then moves at a quarter of the speed,
    /// so it's clear the action is armed without letting the row fly off screen.
    init(translation: CGFloat) {
        let threshold = translation > 0 ? Self.saveThreshold : Self.commentsThreshold
        let magnitude = abs(translation)
        let resisted = magnitude <= threshold ? magnitude : threshold + (magnitude - threshold) / 4
        offset = translation < 0 ? -resisted : resisted
    }

    /// The action that fires if the finger lifts now.
    var armedAction: Action? {
        if offset >= Self.saveThreshold { return .save }
        if offset <= -Self.commentsThreshold { return .comments }
        return nil
    }

    /// Heart behind the left edge: slides in from -80 to 0 and fades in after the first 10 points.
    var heartTranslation: CGFloat {
        clamp(offset - Self.saveThreshold, -Self.saveThreshold, 0)
    }

    var heartAlpha: CGFloat {
        clamp((offset - 10) / (Self.saveThreshold - 10), 0, 1)
    }

    /// Comment count behind the right edge: grows from nothing to full size over the first 80 points.
    var commentCountScale: CGFloat {
        clamp(-offset / 80, 0, 1)
    }

    private func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}
