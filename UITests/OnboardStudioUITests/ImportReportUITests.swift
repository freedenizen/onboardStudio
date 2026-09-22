import XCTest

/// #149: a file that imports badly explains itself, and one that does not stays quiet.
final class ImportReportUITests: OnboardStudioUITestCase {
    @MainActor
    func testExplainsWhatBecameOfEachColumn() throws {
        launch()
        testing("Add Fixture Data (Noisy CAN)")
        XCTAssertTrue(
            sidebarInput("racechrono-v3-noisy").waitForExistence(timeout: Self.timeout), "Data not listed")
        sidebarInput("racechrono-v3-noisy").click()

        let summary = app.staticTexts["import.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout), "No import summary")
        reveal(summary)
        let text = text(of: summary)
        XCTAssertTrue(text.contains("31 columns"), "Summary did not count the columns: \(text)")
        XCTAssertTrue(text.contains("worth a look"), "Summary did not flag anything: \(text)")

        // By default only the columns with something to say; the rest are simply fine.
        let showAll = app.descendants(matching: .any).matching(identifier: "import.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout), "No way to see every column")
        let shownByDefault = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'import.'")
        ).count
        reveal(showAll)
        showAll.click()
        let shownAfter = app.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'import.'")
        ).count
        XCTAssertGreaterThan(shownAfter, shownByDefault, "Showing every column revealed nothing new")
    }

    /// The brake pressure this fixture logs in kPa is the milestone's own example, and the only
    /// committed fixture channel with more than one unit to choose between.
    @MainActor
    func testAPressureChannelCanBeShownInBar() throws {
        launch()
        testing("Add Fixture Data (Noisy CAN)")
        XCTAssertTrue(sidebarInput("racechrono-v3-noisy").waitForExistence(timeout: Self.timeout))
        sidebarInput("racechrono-v3-noisy").click()

        let reads = app.popUpButtons["attribute.canbus:brake_pressure_front.sourceUnit"]
        XCTAssertTrue(reads.waitForExistence(timeout: Self.timeout), "No brake pressure row in the attribute table")
        let shows = app.popUpButtons["attribute.canbus:brake_pressure_front.displayUnit"]
        XCTAssertTrue(shows.waitForExistence(timeout: Self.timeout), "No display unit for the pressure")
        reveal(shows)
        shows.click()
        let bar = shows.menus.menuItems["bar"]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.timeout), "kPa was not offered bar")
        bar.click()

        let row = app.staticTexts["attribute.canbus:brake_pressure_front"]
        XCTAssertTrue(text(of: row).contains("kPa → bar"), "The row does not report the conversion: \(text(of: row))")
    }
}
