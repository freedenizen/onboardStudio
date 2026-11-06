import XCTest

// ci-shard: 1
/// J44: am I getting quicker, and where — the Logbook's Trends view across visits to a circuit
/// (#353, #332).
final class LogbookTrendsUITests: OnboardStudioUITestCase {
    @MainActor
    func testTrendsReadAcrossTwoVisits() throws {
        launch()
        testing("Add Fixture Second Visit")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout))
        expectStatus(containing: "in the logbook")

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        // The segmented control's segments are radio buttons.
        let trends = app.radioButtons["Trends"].exists ? app.radioButtons["Trends"] : app.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: Self.timeout), "No Trends view")
        trends.click()
        // One circuit in the logbook, so the trends are of it without choosing: the chart and the corners.
        let chart = app.descendants(matching: .any).matching(identifier: "logbook.trends.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: Self.timeout), "No lap-time chart")
        let summary = app.staticTexts["logbook.trends.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout))
        // Both fixture sessions carry no date, so both are the day they were entered (#424).
        XCTAssertTrue((summary.value as? String ?? "").contains("2 sessions"), summary.value as? String ?? "")
        let corner = app.descendants(matching: .any).matching(identifier: "logbook.trends.corner.1").firstMatch
        XCTAssertTrue(corner.waitForExistence(timeout: Self.timeout), "No corner row")
        let sessions = app.radioButtons["Sessions"].exists ? app.radioButtons["Sessions"] : app.buttons["Sessions"]
        sessions.click()
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout))
    }
}
