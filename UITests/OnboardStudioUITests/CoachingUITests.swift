import XCTest

// ci-shard: 3
/// J33: find where the time went — the Coaching window reads a lap against the best lap, names
/// the corners that cost the most, and takes the playhead there (#321).
final class CoachingUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheCoachingWindowRanksCornersAndShowsThem() throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")

        menu("Project", "Coaching…")
        let table = app.descendants(matching: .any).matching(identifier: "coaching.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout * 2), "The Coaching window did not read the laps")
        let headline = app.staticTexts["coaching.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: Self.timeout))
        // A static text's string is its value on macOS; its label is empty.
        func headlineText() -> String { headline.value as? String ?? headline.label }
        // The lap at the playhead (lap 1, a fast lap) against the best lap: not the slow lap yet.
        XCTAssertTrue(headlineText().hasPrefix("Lap "), headlineText())
        XCTAssertFalse(headlineText().hasPrefix("Lap 2 "), headlineText())

        // The slow lap has plenty to say: two corners, the biggest loss first, with a way to see it.
        choosePopUpItem("Lap 2 — 0:44.60", in: app.popUpButtons["coaching.lap"])
        // A card's Show Me button is the element to wait for: a button always carries its identifier.
        let showMe = app.buttons["coaching.showMe.1"]
        XCTAssertTrue(showMe.waitForExistence(timeout: Self.timeout * 2), "No opportunity for the slow lap")
        XCTAssertTrue(headlineText().hasPrefix("Lap 2 "), headlineText())
        XCTAssertEqual(transportTime.value as? String, "0:00.00")
        showMe.click()
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", "0:00.00"), object: transportTime)
        XCTAssertEqual(
            XCTWaiter().wait(for: [moved], timeout: Self.timeout), .completed, "Show Me did not move the playhead")

        // Show Me also selects the corner, which opens its detail: the phases, both laps' readings,
        // the two lines, and the way to the video.
        let detail = app.staticTexts["Time lost by phase"]
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "Selecting a corner showed no detail")
        // The legend under the corner's map keeps each entry whole, on one line (#457: "Slow / est").
        let slowest = app.staticTexts.matching(NSPredicate(format: "value == 'Slowest'")).firstMatch
        XCTAssertTrue(slowest.waitForExistence(timeout: Self.timeout), "No legend under the corner's map")
        XCTAssertLessThan(slowest.frame.height, 22, "A legend entry is broken over two lines")
        let compareInVideo = app.buttons["coaching.compareInVideo"]
        XCTAssertTrue(compareInVideo.waitForExistence(timeout: Self.timeout), "No Compare in Video for a real lap")
        compareInVideo.click()
        XCTAssertTrue(sidebarObject("Compared Lap Picture").waitForExistence(timeout: Self.timeout), "No comparison")
        menu("Edit", "Undo Compare Laps")
        XCTAssertTrue(sidebarObject("Compared Lap Picture").waitForNonExistence(timeout: Self.timeout))

        // The reference is a choice too, and both choices are one undo step each.
        choosePopUpItem("Fastest rolling lap", in: app.popUpButtons["coaching.reference"])
        let rolling = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "the rolling lap"), object: headline)
        XCTAssertEqual(XCTWaiter().wait(for: [rolling], timeout: Self.timeout * 2), .completed, headlineText())
        menu("Edit", "Undo Change Coaching Reference")
        let best = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "your best lap"), object: headline)
        XCTAssertEqual(XCTWaiter().wait(for: [best], timeout: Self.timeout * 2), .completed, headlineText())
        // Lining the laps up by position is a choice and an undo step too (#333).
        let byPosition = app.checkBoxes["coaching.alignByPosition"]
        XCTAssertTrue(byPosition.waitForExistence(timeout: Self.timeout), "No Line up by position toggle")
        byPosition.click()
        let positioned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "by position"),
            object: app.staticTexts["coaching.alignment"])
        XCTAssertEqual(XCTWaiter().wait(for: [positioned], timeout: Self.timeout * 2), .completed)
        menu("Edit", "Undo Change Coaching Alignment")
        let distanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "by distance"),
            object: app.staticTexts["coaching.alignment"])
        XCTAssertEqual(XCTWaiter().wait(for: [distanced], timeout: Self.timeout * 2), .completed)
        menu("Edit", "Undo Change Coaching Lap")
        let notSlow = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (value BEGINSWITH %@)", "Lap 2 "), object: headline)
        XCTAssertEqual(XCTWaiter().wait(for: [notSlow], timeout: Self.timeout * 2), .completed, headlineText())
    }
}
