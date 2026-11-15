import XCTest

// ci-shard: 2
/// J70: a 0–60 and a quarter mile from a straight-line log, in the Logbook (#553).
final class PerformanceUITests: OnboardStudioUITestCase {
    @MainActor
    func testAStraightLineLogIsTimedLikeAPerformanceMeter() throws {
        launch()
        testing("Add Fixture Drag Runs to Logbook")
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

        // A log with no laps is measured on its own: both starts, the quicker one's 0–60 (or 0–100
        // km/h, by the Mac's speed unit) as arithmetic gives it, and the shorter stop.
        let detail = app.descendants(matching: .any).matching(identifier: "logbook.detail").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "No detail for the session")
        XCTAssertTrue(detail.staticTexts["Start 2"].waitForExistence(timeout: Self.timeout), "No attempts listed")
        // Each number is read aloud with its measure, and the best says so.
        let launch = detail.staticTexts.matching(
            NSPredicate(format: "value IN %@", ["0–60 mph 5.36 s, best", "0–100 km/h 5.56 s, best"])
        ).firstMatch
        XCTAssertTrue(launch.exists, "No best 0–60 of 5.36 s (or 0–100 km/h of 5.56 s)")
        let stop = detail.staticTexts.matching(
            NSPredicate(format: "value IN %@", ["60–0 mph distance 118 ft, best", "100–0 km/h distance 38.6 m, best"])
        ).firstMatch
        XCTAssertTrue(stop.exists, "No best 60–0 of 118 ft (or 100–0 km/h of 38.6 m)")

        // Turned off, the numbers go; Undo brings them back.
        let measure = detail.descendants(matching: .any).matching(identifier: "logbook.performance.measure").firstMatch
        XCTAssertTrue(measure.waitForExistence(timeout: Self.timeout), "No Performance runs switch")
        reveal(measure)
        measure.click()
        XCTAssertTrue(
            detail.staticTexts["Start 2"].waitForNonExistence(timeout: Self.timeout), "Turning it off kept the numbers")
        menu("Edit", "Undo Turn Off Performance Runs")
        XCTAssertTrue(
            detail.staticTexts["Start 2"].waitForExistence(timeout: Self.timeout), "Undo did not bring them back")
    }
}
