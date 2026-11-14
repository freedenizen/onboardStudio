import XCTest

// ci-shard: 5
/// J68: a file with no gates timed in runs from lines the driving suggests (#552).
final class SuggestedRunLinesUITests: OnboardStudioUITestCase {
    @MainActor
    func testChoosingRunsSuggestsTheStartAndTheFinish() throws {
        launch()
        testing("Add Fixture Data (Autocross, No Gates)")
        let input = sidebarInput("autocross-no-gates")
        XCTAssertTrue(input.waitForExistence(timeout: Self.timeout), "Data not listed")
        input.click()

        // No gates in the file: it starts in laps, with nothing to time.
        let group = app.radioGroups["data.timing"]
        let timing = group.exists ? group : app.otherElements["data.timing"]
        reveal(timing)
        XCTAssertTrue(timing.waitForExistence(timeout: Self.timeout), "No Timing choice")
        timing.radioButtons["Runs"].click()
        expectStatus(containing: "Suggested a start where 3 runs set off")

        let runOne = app.staticTexts["Run 1"]
        reveal(runOne)
        XCTAssertTrue(runOne.waitForExistence(timeout: Self.timeout), "The suggested lines time no runs")
        XCTAssertTrue(app.staticTexts["DNF"].exists, "The off-course run is not a DNF")
        XCTAssertTrue(app.buttons["data.suggestRunLines"].exists, "No way to ask again")
        menu("Edit", "Undo Time in Runs")
        XCTAssertTrue(runOne.waitForNonExistence(timeout: Self.timeout), "Undo left the runs")
    }
}
