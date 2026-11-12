import XCTest

// ci-shard: 2
/// J58: see how the new day went (#459). The report of Add Files to Logbook says, for each
/// circuit, how the day's best compares with the visit before it, and Show Trends or Show Season
/// opens the Logbook where the progress can be read.
final class ImportProgressUITests: OnboardStudioUITestCase {
    private var summary: XCUIElement { app.staticTexts["trackday.summary"] }
    private var progress: XCUIElement { app.staticTexts.matching(identifier: "trackday.progress").firstMatch }
    private var showProgress: XCUIElement { app.buttons["trackday.showProgress"] }

    /// A first session somewhere: the report says so, and Show Season opens the Logbook — from a
    /// project, where there was no Logbook window.
    @MainActor
    func testAFirstVisitLeadsToTheSeason() throws {
        launch()
        testing("Add Fixture Second Visit")
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout * 3), "No import report")
        XCTAssertTrue(progress.waitForExistence(timeout: Self.timeout), "The report says nothing of progress")
        let line = progress.value as? String ?? ""
        XCTAssertTrue(line.hasPrefix("First visit to "), line)
        XCTAssertTrue(line.contains("Trends begins with your next day there"), line)
        XCTAssertEqual(showProgress.label, "Show Season")
        showProgress.click()

        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook window")
        XCTAssertFalse(summary.exists, "The report stayed open")
        let season = app.descendants(matching: .any).matching(identifier: "logbook.season").firstMatch
        XCTAssertTrue(season.waitForExistence(timeout: Self.timeout), "The Logbook is not on the Season")
    }

    /// A second session at the circuit: the report gives the day's best, and Show Trends opens the
    /// circuit's Trends with its chart.
    @MainActor
    func testASecondSessionLeadsToTheCircuitsTrends() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout * 3), "No import report")
        done.click()
        testing("Add Fixture Second Visit")
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout * 3), "No report of the second visit")
        XCTAssertTrue(progress.waitForExistence(timeout: Self.timeout), "The report says nothing of progress")
        let line = progress.value as? String ?? ""
        XCTAssertTrue(line.contains("best lap"), line)
        XCTAssertTrue(line.contains("2 sessions"), line)
        XCTAssertEqual(showProgress.label, "Show Trends")
        showProgress.click()

        XCTAssertFalse(summary.waitForExistence(timeout: 1), "The report stayed open")
        let chart = app.descendants(matching: .any).matching(identifier: "logbook.trends.chart").firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: Self.timeout), "The Logbook is not on the circuit's Trends")
        let trendsSummary = app.staticTexts["logbook.trends.summary"]
        XCTAssertTrue(trendsSummary.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(
            (trendsSummary.value as? String ?? "").contains("2 sessions"), trendsSummary.value as? String ?? "")
    }
}
