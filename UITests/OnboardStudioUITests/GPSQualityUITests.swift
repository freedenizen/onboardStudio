import XCTest

// ci-shard: 4
/// J74: see how good a session's GPS is (#555). The import report rates the file's positions and
/// says what counts against them, so a driver knows how far a brake point read from them is worth.
final class GPSQualityUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheImportReportSaysHowGoodTheGPSIs() throws {
        launch()
        // Two positions a second: fine for a lap time, too coarse for a brake point.
        addFixtureData()
        sidebarInput("racerender-basic").click()
        menu("Project", "Show Import Report…")
        expectAttributeWindow()
        chooseScope("racerender-basic")
        let tab = app.radioButtons["Import"].exists ? app.radioButtons["Import"] : app.buttons["Import"]
        if tab.exists { tab.click() }

        let gps = app.descendants(matching: .any).matching(identifier: "gps.quality").firstMatch
        XCTAssertTrue(gps.waitForExistence(timeout: Self.timeout), "No GPS line in the import report")
        let words = gps.label
        XCTAssertTrue(words.contains("GPS: Poor"), "Not rated poor: \(words)")
        XCTAssertTrue(words.contains("2 positions a second"), "No rate: \(words)")
        XCTAssertTrue(words.contains("corner-level advice needs 10 or more"), "Not said why: \(words)")
    }

    @MainActor
    func testTheLogbookSaysHowGoodEachSessionsGPSIs() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        // Five positions a second, with one that jumps: fair.
        testing("Add Fixture Session at a Circuit")
        let report = app.descendants(matching: .any).matching(identifier: "trackday.report").firstMatch
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        let added = report.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'GPS fair' OR value CONTAINS 'GPS fair'")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: Self.timeout), "The import line does not say the GPS is fair")
        app.buttons["trackday.done"].click()

        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        let badge = rows.firstMatch.descendants(matching: .any)
            .matching(NSPredicate(format: "label == 'GPS Fair'")).firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: Self.timeout), "No GPS rating in the session's row")
        rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        let gps = app.descendants(matching: .any).matching(identifier: "logbook.detail.gps").firstMatch
        XCTAssertTrue(gps.waitForExistence(timeout: Self.timeout), "No GPS row in the session's details")
        XCTAssertTrue(gps.label.contains("5 positions a second"), "Not said what was measured: \(gps.label)")
        XCTAssertTrue(gps.label.contains("further away than the car could have got to"), "No jump: \(gps.label)")
    }
}
