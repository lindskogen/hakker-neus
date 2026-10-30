import CoreGraphics
import Testing
@testable import HakkerNeus

struct StorySwipeTests {
    @Test func followsTheFingerUpToTheLastThreshold() {
        #expect(StorySwipe(translation: 120).offset == 120)
        #expect(StorySwipe(translation: -100).offset == -100)
    }

    @Test func resistsPastTheLastThreshold() {
        #expect(StorySwipe(translation: 200).offset == 170)
        #expect(StorySwipe(translation: -140).offset == -110)
    }

    @Test(arguments: [
        (0, nil),
        (79, nil),
        (80, StorySwipe.Action.save),
        (159, .save),
        (160, .upvote),
        (300, .upvote),
        (-99, nil),
        (-100, .comments),
        (-300, .comments),
    ] as [(CGFloat, StorySwipe.Action?)])
    func armsActionsAtTheRNThresholds(translation: CGFloat, action: StorySwipe.Action?) {
        #expect(StorySwipe(translation: translation).armedAction == action)
    }

    /// Interpolations from `renderLeftActions` / `renderRightActions` in ListItem.tsx.
    @Test func actionAnimationsMatchTheRNInterpolations() {
        #expect(StorySwipe(translation: 0).heartTranslation == -80)
        #expect(StorySwipe(translation: 40).heartTranslation == -40)
        #expect(StorySwipe(translation: 200).heartTranslation == 0)

        #expect(StorySwipe(translation: 10).heartAlpha == 0)
        #expect(StorySwipe(translation: 45).heartAlpha == 0.5)
        #expect(StorySwipe(translation: 80).heartAlpha == 1)
        #expect(StorySwipe(translation: -50).heartAlpha == 0)

        #expect(StorySwipe(translation: 0).commentCountScale == 0)
        #expect(StorySwipe(translation: -40).commentCountScale == 0.5)
        #expect(StorySwipe(translation: -200).commentCountScale == 1)
        #expect(StorySwipe(translation: 50).commentCountScale == 0)
    }
}
