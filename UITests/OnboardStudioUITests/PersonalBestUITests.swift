import XCTest

// ci-shard: 2
/// J42: a personal best is a question over the logbook — the session that set one is badged, the
/// detail says what the best here is (#351).
final class PersonalBestUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheLogbookBadgesAndNamesThePersonalBest() throws {
        launch()
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        // Every fixture is its own circuit, so each with laps set a personal best: the star column.
        let stars = table.descendants(matching: .image).matching(NSPredicate(format: "label == %@", "Personal best"))
        let badged = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: stars)
        XCTAssertEqual(XCTWaiter().wait(for: [badged], timeout: Self.timeout), .completed, "No PB badge")
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let detail = app.staticTexts["Personal best here"]
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "The detail does not name the personal best")
    }
}
