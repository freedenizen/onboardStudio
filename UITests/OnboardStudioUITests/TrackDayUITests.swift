import XCTest

// ci-shard: 3
/// J37: a track day into the logbook — files and folders in, a line per file out (#346).
final class TrackDayUITests: OnboardStudioUITestCase {
    @MainActor
    func testAFolderOfSessionsIsEnteredAndReportedPerFile() throws {
        launch()
        // The Testing menu stands in for the open panel: the fixtures folder is the track day.
        // The command the journey names lives in File, with the other ways of bringing files in;
        // the hook below stands in for its open panel.
        let file = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(file.waitForExistence(timeout: Self.timeout), "No File menu")
        file.click()
        XCTAssertTrue(
            file.menus.menuItems["Add Track Day to Logbook…"].waitForExistence(timeout: Self.timeout),
            "File ▸ Add Track Day to Logbook… is missing")
        app.typeKey(.escape, modifierFlags: [])
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        let summary = app.staticTexts["trackday.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout * 3), "The import did not finish")
        let text = summary.value as? String ?? summary.label
        XCTAssertTrue(text.contains("sessions added"), text)
        XCTAssertFalse(text.hasPrefix("0 "), text)
        done.click()
        XCTAssertTrue(done.waitForNonExistence(timeout: Self.timeout))
        expectStatus(containing: "to the logbook")
    }
}
