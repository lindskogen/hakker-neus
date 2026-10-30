import XCTest

/// Runs against the debug comments sink (`-CommentsSink`), so comment content is fixed.
@MainActor
final class CommentRenderingUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-CommentsSink"]
        app.launch()
        XCTAssertTrue(sinkHeader.waitForExistence(timeout: 10))
    }

    private var sinkHeader: XCUIElement {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier == 'comments.header' AND label == 'Comments sink'"))
            .firstMatch
    }

    private func comment(by author: String) -> XCUIElement {
        app.collectionViews["comments.list"].cells.matching(NSPredicate(format: "label BEGINSWITH %@", author)).firstMatch
    }

    func testExternalLinkOpensInAppBrowser() {
        let link = app.links["an external link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.tap()

        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
    }

    func testHackerNewsLinkOpensCommentsInApp() {
        let link = app.links.matching(NSPredicate(format: "label CONTAINS 'news.ycombinator.com'")).firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        // The link wraps onto two lines; the center of its bounding box isn't on the link text.
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.25)).tap()

        // A new comments screen replaces the sink rather than a browser opening.
        XCTAssertTrue(sinkHeader.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Done"].exists)
        XCTAssertTrue(app.collectionViews["comments.list"].waitForExistence(timeout: 5))
    }

    /// Taps near the start of a link, which may wrap onto two lines.
    private func tapLink(_ label: String) {
        let link = app.links[label]
        XCTAssertTrue(link.waitForExistence(timeout: 5), "No link '\(label)'")
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.3)).tap()
    }

    func testLinkToACommentOpensItsStoryScrolledToIt() {
        tapLink("a reply below")

        // A new screen for the same story, scrolled away from the header to the linked comment.
        // (It's the last comment, so it can't scroll all the way to the top.)
        let scrolledPastHeader = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == false"), object: sinkHeader)
        wait(for: [scrolledPastHeader], timeout: 5)

        let reply = comment(by: "user4")
        XCTAssertTrue(reply.exists)
        XCTAssertLessThanOrEqual(reply.frame.maxY, app.windows.firstMatch.frame.maxY, "Linked comment isn't fully on screen")
        XCTAssertFalse(app.buttons["Done"].exists, "Opened a browser instead of the comment")
    }

    func testSelfPostShowsItsTextWithLinks() {
        tapLink("a self post")

        XCTAssertTrue(app.staticTexts["Ask HN: Self post sink"].waitForExistence(timeout: 5))
        tapLink("the docs")
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 10))
    }

    func testNextThreadButtonScrollsToTheNextTopLevelComment() {
        let button = app.buttons["comments.nextThread"]
        XCTAssertTrue(button.waitForExistence(timeout: 5))

        // From the top, the first thread is still below the header, so it comes first.
        button.tap()
        sleep(1)
        // Before the tap it sits below the header, at about 190pt.
        let firstThread = comment(by: "op")
        XCTAssertLessThan(firstThread.frame.minY, 120, "First thread wasn't scrolled to the top")

        // user3 starts the second top-level thread in the sink. It's near the end of the list,
        // so it moves up as far as the list can scroll rather than all the way to the top.
        let secondThread = comment(by: "user3")
        let before = secondThread.frame.minY
        button.tap()
        sleep(1)
        XCTAssertLessThan(secondThread.frame.minY, before - 100, "Second tap didn't scroll towards the next thread")
    }

    func testLongPressingALinkShowsItsMenu() {
        let link = app.links["an external link"]
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        link.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)).press(forDuration: 1.2)

        XCTAssertTrue(app.buttons["Open in Safari"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Link"].exists)
        XCTAssertTrue(app.buttons["Copy Link"].exists)
        XCTAssertTrue(app.buttons["Share"].exists)
    }

    func testTappingBodyTextOutsideLinksCollapses() {
        let cell = comment(by: "user3")
        XCTAssertTrue(cell.waitForExistence(timeout: 5))

        // Plain text inside the body (not a link) should fall through to the cell.
        cell.textViews.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2)).tap()
        XCTAssertTrue((cell.value as? String ?? "").hasPrefix("Collapsed"))
    }

    func testScrolledCodeBlockScrollsBackInsteadOfGoingBack() {
        let code = app.scrollViews.matching(NSPredicate(format: "label == 'Code' AND value BEGINSWITH 'curl'")).firstMatch
        if !code.isHittable { app.swipeUp() }
        XCTAssertTrue(code.waitForExistence(timeout: 5))

        code.swipeLeft()
        code.swipeRight()

        XCTAssertTrue(sinkHeader.exists, "Dragging right in a scrolled code block popped the screen")
    }
}
