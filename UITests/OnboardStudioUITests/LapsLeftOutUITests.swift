import XCTest

// ci-shard: 2
/// J72: leave a lap that does not count out of the session's figures (#554).
final class LapsLeftOutUITests: OnboardStudioUITestCase {
    @MainActor
    func testALapLeftOutIsNoLongerTheBest() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Session at a Circuit")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        app.buttons["trackday.done"].click()

        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        // The best lap, as the session reads it now: "lap 2", say.
        let bestLap = app.staticTexts["logbook.detail.best.detail"]
        XCTAssertTrue(bestLap.waitForExistence(timeout: Self.timeout), "No best lap in the session's detail")
        let best = text(of: bestLap)
        let number = try XCTUnwrap(best.split(separator: " ").last.map(String.init), "Best lap reads '\(best)'")

        // Leave it out: it was off the track.
        let counts = app.menuButtons["logbook.lap.\(number).counts"]
        reveal(counts)
        XCTAssertTrue(counts.waitForExistence(timeout: Self.timeout), "No way to leave lap \(number) out")
        counts.click()
        let offTrack = counts.menus.menuItems["Off Track"]
        XCTAssertTrue(offTrack.waitForExistence(timeout: Self.timeout), "No Off Track reason")
        offTrack.click()

        let leftOut = app.staticTexts["logbook.lap.\(number).leftOut"]
        XCTAssertTrue(leftOut.waitForExistence(timeout: Self.timeout * 2), "Lap \(number) does not say it is left out")
        XCTAssertEqual(text(of: leftOut), "left out: off track")
        let moved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@ AND label != %@", best, best), object: bestLap)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: Self.timeout), .completed, "Lap \(number) is still best")

        // One step of Undo counts it again.
        menu("Edit", "Undo Leave Lap \(number) Out")
        XCTAssertTrue(leftOut.waitForNonExistence(timeout: Self.timeout * 2), "Undo left lap \(number) out")
        let back = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@ OR label == %@", best, best), object: bestLap)
        XCTAssertEqual(
            XCTWaiter().wait(for: [back], timeout: Self.timeout), .completed, "Undo did not restore the best")
    }
}
