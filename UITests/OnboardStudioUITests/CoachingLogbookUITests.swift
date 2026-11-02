import XCTest

// ci-shard: 3
/// J43: a lap read against a session from the logbook — the personal best here, the last visit —
/// without adding its file to the project (#352).
final class CoachingLogbookUITests: OnboardStudioUITestCase {
    @MainActor
    func testALogbookSessionIsAReference() throws {
        launch()
        addFixtureVideo()
        // A second visit at the same place, in the logbook only.
        testing("Add Fixture Second Visit")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        // This visit, in the project.
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")
        expectStatus(containing: "in the logbook")

        menu("Project", "Coaching…")
        let reference = app.popUpButtons["coaching.reference"]
        XCTAssertTrue(reference.waitForExistence(timeout: Self.timeout * 2), "The Coaching window did not open")
        reference.click()
        let logbookItem = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH %@", "Personal best here"))
            .firstMatch
        XCTAssertTrue(logbookItem.waitForExistence(timeout: Self.timeout), "No Logbook section in Compared with")
        logbookItem.click()
        let headline = app.staticTexts["coaching.headline"]
        let read = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "coaching-laps"), object: headline)
        XCTAssertEqual(
            XCTWaiter().wait(for: [read], timeout: Self.timeout * 3), .completed, headline.value as? String ?? "")
        let alignment = app.staticTexts["coaching.alignment"]
        XCTAssertTrue(alignment.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue((alignment.value as? String ?? "").contains("position"), alignment.value as? String ?? "")
        menu("Edit", "Undo Change Coaching Reference")
        let back = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "your best lap"), object: headline)
        XCTAssertEqual(XCTWaiter().wait(for: [back], timeout: Self.timeout * 2), .completed)
    }
}
