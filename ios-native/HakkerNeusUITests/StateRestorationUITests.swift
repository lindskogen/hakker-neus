import XCTest

/// Background the app (which is when it saves its state), close it, and relaunch.
@MainActor
final class StateRestorationUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
    }

    private var frontPage: XCUIElement { app.collectionViews["stories.list"] }
    private var commentsList: XCUIElement { app.collectionViews["comments.list"] }

    /// Label of the comment nearest the top of the screen.
    private func topCommentLabel() -> String? {
        let windowTop = app.windows.firstMatch.frame.minY
        return commentsList.cells.allElementsBoundByIndex
            .filter { $0.frame.maxY > windowTop + 70 && $0.identifier != "comments.header" }
            .min { $0.frame.minY < $1.frame.minY }?
            .label
    }

    /// Label of the story nearest the top of the screen.
    private func topStoryLabel() -> String? {
        let windowTop = app.windows.firstMatch.frame.minY
        return frontPage.cells.allElementsBoundByIndex
            .filter { $0.frame.maxY > windowTop + 70 }
            .min { $0.frame.minY < $1.frame.minY }?
            .label
    }

    func testFrontPageComesBackUnchangedAndAtTheSamePlace() throws {
        app.launchArguments = ["-NoStateRestoration"]
        app.launch()
        XCTAssertTrue(frontPage.cells.firstMatch.waitForExistence(timeout: 15))
        for _ in 0..<4 { frontPage.swipeUp(velocity: .slow) }
        sleep(2)
        let expected = try XCTUnwrap(topStoryLabel())

        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(frontPage.cells.firstMatch.waitForExistence(timeout: 10))
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.topStoryLabel() == expected },
            object: nil
        )
        wait(for: [restored], timeout: 10)

        // Back to the top for other runs.
        for _ in 0..<6 { frontPage.swipeDown(velocity: .fast) }
        XCUIDevice.shared.press(.home)
        sleep(1)
    }

    func testCommentsScreenAndScrollPositionSurviveARelaunch() throws {
        app.launchArguments = ["-NoStateRestoration"]
        app.launch()
        let story = frontPage.cells.firstMatch
        XCTAssertTrue(story.waitForExistence(timeout: 15))

        // Open the top story's comments and scroll a few screens down.
        let start = story.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: story.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(commentsList.cells.element(boundBy: 2).waitForExistence(timeout: 15))
        for _ in 0..<3 { commentsList.swipeUp(velocity: .slow) }
        sleep(2)
        let expected = try XCTUnwrap(topCommentLabel())

        // Going to the background saves the state; then close and reopen the app.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.terminate()
        app.launchArguments = []
        app.launch()

        XCTAssertTrue(commentsList.waitForExistence(timeout: 10), "Didn't come back to the comments screen")
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in self.topCommentLabel() == expected },
            object: nil
        )
        wait(for: [restored], timeout: 15)

        // Leave the app on the front page for other runs.
        let back = app.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.5))
        back.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)), withVelocity: .fast, thenHoldForDuration: 0)
        XCTAssertTrue(frontPage.waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        sleep(1)
    }
}
