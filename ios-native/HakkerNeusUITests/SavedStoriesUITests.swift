import XCTest

/// Saved list navigation. Runs against the live front page; leaves nothing saved behind.
@MainActor
final class SavedStoriesUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(frontPage.cells.firstMatch.waitForExistence(timeout: 15))
    }

    private var frontPage: XCUIElement { app.collectionViews["stories.list"] }
    private var savedList: XCUIElement { app.collectionViews["saved.list"] }

    private func drag(from startX: CGFloat, to endX: CGFloat, on element: XCUIElement? = nil, dy: CGFloat = 0.5) {
        let target: XCUIElement = element ?? app
        let start = target.coordinate(withNormalizedOffset: CGVector(dx: startX, dy: dy))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: endX, dy: dy))
        start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .fast, thenHoldForDuration: 0)
    }

    private func isHittable(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: element)
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    func testEdgeSwipesMoveBetweenFrontPageAndSavedList() {
        drag(from: 0.0, to: 0.9)
        XCTAssertTrue(savedList.waitForExistence(timeout: 3), "Left-edge swipe didn't reveal the saved list")

        drag(from: 1.0, to: 0.1)
        XCTAssertTrue(isHittable(frontPage.cells.firstMatch), "Right-edge swipe didn't return to the front page")
    }

    func testMidScreenRightSwipeOnFrontPageSavesInsteadOfGoingBack() {
        let story = frontPage.cells.firstMatch
        let wasSaved = (story.value as? String ?? "").hasSuffix(", saved")

        drag(from: 0.3, to: 0.9, on: story)
        XCTAssertFalse(savedList.waitForExistence(timeout: 1))

        // Put it back.
        let toggled = (story.value as? String ?? "").hasSuffix(", saved") != wasSaved
        XCTAssertTrue(toggled)
        drag(from: 0.3, to: 0.9, on: story)
    }

    func testSavedStoryShowsUpAndCanBeUnsavedFromTheSavedList() {
        let story = frontPage.cells.firstMatch
        let title = story.label
        if !(story.value as? String ?? "").hasSuffix(", saved") {
            drag(from: 0.3, to: 0.9, on: story)
        }

        drag(from: 0.0, to: 0.9)
        let saved = savedList.cells.matching(NSPredicate(format: "label == %@", title)).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 3))

        drag(from: 0.3, to: 0.9, on: saved)
        XCTAssertTrue(saved.waitForNonExistence(timeout: 3), "Unsaving didn't remove the row from the saved list")
    }
}
