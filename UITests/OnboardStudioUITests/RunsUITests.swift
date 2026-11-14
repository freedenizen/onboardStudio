import XCTest

// ci-shard: 4
/// J65: time an autocross in runs, from a start line to a finish line (#552).
final class RunsUITests: OnboardStudioUITestCase {
    @MainActor
    func testAFileWithAStartAndAFinishIsTimedInRuns() throws {
        launch()
        testing("Add Fixture Data (Autocross)")
        let input = sidebarInput("autocross")
        XCTAssertTrue(input.waitForExistence(timeout: Self.timeout), "Data not listed")
        // The file's own gates: a separate finish line makes it a point-to-point course. (What the
        // status line said of them is soon replaced by the logbook's word on the file.)
        input.click()

        let runOne = app.staticTexts["Run 1"]
        reveal(runOne)
        XCTAssertTrue(runOne.waitForExistence(timeout: Self.timeout), "The inspector lists no runs")
        XCTAssertTrue(app.staticTexts["Run 3"].exists, "The third run is missing")
        XCTAssertTrue(app.staticTexts["DNF"].exists, "The run that never reached the finish is not a DNF")
        XCTAssertFalse(app.staticTexts["Run -1"].exists, "The driving between runs is listed")

        // Back to laps, and undo it by name.
        let timing = timingControl()
        reveal(timing)
        timing.radioButtons["Laps"].click()
        XCTAssertTrue(
            app.staticTexts["Run 1"].waitForNonExistence(timeout: Self.timeout), "Choosing Laps left the runs listed")
        menu("Edit", "Undo Time in Laps")
        XCTAssertTrue(app.staticTexts["Run 1"].waitForExistence(timeout: Self.timeout), "Undo did not bring runs back")

        // ⌥↓ steps run to run, and says which.
        menu("Marker", "Next Lap")
        expectStatus(containing: "Run 1")
    }

    /// The Laps / Runs control: a segmented picker, reported as a radio group or a group by macOS.
    func timingControl() -> XCUIElement {
        let group = app.radioGroups["data.timing"]
        return group.exists ? group : app.otherElements["data.timing"]
    }
}
