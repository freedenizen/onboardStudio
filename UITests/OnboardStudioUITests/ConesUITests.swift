import XCTest

// ci-shard: 4
/// J67: count an autocross run's cones and say it went off course (#552).
final class ConesUITests: OnboardStudioUITestCase {
    @MainActor
    func testConesAndAnOffCourseDecideWhichRunCounts() throws {
        launch()
        testing("Add Fixture Autocross to Logbook")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout * 3), "No Add Track Day sheet")
        done.click()

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        // Run 1 is the quicker clean run; a cone on it makes it 0:53.97, and run 2 the best.
        let official = app.staticTexts["logbook.run.1.official"]
        reveal(official)
        XCTAssertTrue(official.waitForExistence(timeout: Self.timeout), "No runs with their official times")
        let clean = text(of: official)
        let cones = app.steppers["logbook.run.1.cones"]
        XCTAssertTrue(cones.exists, "No cones for run 1")
        cones.incrementArrows.firstMatch.click()
        let changed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@ AND label != %@", clean, clean), object: official)
        XCTAssertEqual(XCTWaiter().wait(for: [changed], timeout: Self.timeout), .completed, "A cone added no time")
        XCTAssertTrue(app.staticTexts["1 cone"].exists, "The run does not say it hit a cone")
        menu("Edit", "Undo Change Cones")
        XCTAssertTrue(app.staticTexts["0 cones"].waitForExistence(timeout: Self.timeout), "Undo left the cone")

        // Off course: a DNF, though it crossed the finish.
        let off = app.checkBoxes["logbook.run.1.offCourse"]
        XCTAssertTrue(off.exists, "No DNF box for run 1")
        off.click()
        let dnf = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'DNF' OR label == 'DNF'"), object: official)
        XCTAssertEqual(XCTWaiter().wait(for: [dnf], timeout: Self.timeout), .completed, "Off course is not a DNF")
        menu("Edit", "Undo Mark Off Course")
    }
}
