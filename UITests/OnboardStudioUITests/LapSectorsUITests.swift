import XCTest

// ci-shard: 2
/// J71: read a session lap by lap (#557). A session in the Logbook lists every lap with its sector
/// times, its gap to the best lap and its top and lowest speed, the best of each column picked
/// out; a session entered before sectors were kept has them read from its file when it is shown.
final class LapSectorsUITests: OnboardStudioUITestCase {
    /// The rows of the Logbook's table of sessions.
    private var rows: XCUIElementQuery {
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        return table.descendants(matching: .any).matching(rowTypes)
    }

    @MainActor
    func testASessionsLapsShowTheirSectorsAndTheBestOfEach() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Session at a Circuit")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        app.buttons["trackday.done"].click()
        // As a build before #557 entered it: the Logbook reads the sectors when the session is shown.
        testing("Forget Every Session's Sectors")

        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No sessions")
        rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let laps = app.descendants(matching: .any).matching(identifier: "logbook.laps").firstMatch
        XCTAssertTrue(laps.waitForExistence(timeout: Self.timeout), "No laps in the session")

        // Lap 3 is the slow one: timed in every sector, and off the best.
        let sector = laps.staticTexts["logbook.lap.3.s1"]
        XCTAssertTrue(sector.waitForExistence(timeout: Self.timeout), "No S1 column")
        // A Text's accessibility label is its value to XCUITest on macOS.
        let timed = NSPredicate(format: "value BEGINSWITH 'S1 ' AND NOT (value CONTAINS 'not timed')")
        expectation(for: timed, evaluatedWith: sector)
        waitForExpectations(timeout: Self.timeout * 2)
        let gap = laps.staticTexts["logbook.lap.3.gap"].value as? String ?? ""
        XCTAssertTrue(gap.contains("off the best"), "No gap to the best: \(gap)")
        // At the detail's usual width the speeds give way, and say so.
        XCTAssertTrue(
            laps.staticTexts["logbook.lap.3.top"].exists || laps.staticTexts["logbook.laps.speedsHidden"].exists,
            "No top speed, and nothing says where it went")

        for name in ["S1", "S2", "S3"] {
            let best = laps.staticTexts.matching(NSPredicate(format: "value ENDSWITH %@", ", the best \(name)"))
            XCTAssertGreaterThan(best.count, 0, "Nothing picks out the best \(name)")
        }
    }
}
