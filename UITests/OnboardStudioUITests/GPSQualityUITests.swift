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
}
