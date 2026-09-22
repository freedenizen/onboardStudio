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

    /// The milestone's own example, end to end under the vocabulary of #191: the attribute is
    /// **Brake pressure (front)**, and `brake_pressure_front` is the column it is mapped to. The
    /// column is not itself an attribute, which is what this used to assume.
    @MainActor
    func testAPressureAttributeIsMappedToAColumnAndShownInBar() throws {
        launch()
        testing("Add Fixture Data (Noisy CAN)")
        XCTAssertTrue(sidebarInput("racechrono-v3-noisy").waitForExistence(timeout: Self.timeout))
        sidebarInput("racechrono-v3-noisy").click()

        // Nothing maps it yet and the file does not supply it by name, so its row waits until
        // every attribute is asked for.
        let showAll = app.descendants(matching: .any).matching(identifier: "attributes.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout), "No way to see every attribute")
        reveal(showAll)
        showAll.click()

        let source = app.popUpButtons["attribute.brakePressureFront.source"]
        XCTAssertTrue(source.waitForExistence(timeout: Self.timeout), "No Brake pressure (front) row")
        reveal(source)
        choosePopUpItem("brake_pressure_front", in: source)

        // Once it is mapped, the unit the file declared for that column is what it reads in, and
        // bar is one of the units it can then be shown in.
        let shows = app.popUpButtons["attribute.brakePressureFront.displayUnit"]
        XCTAssertTrue(shows.waitForExistence(timeout: Self.timeout), "No display unit for the pressure")
        reveal(shows)
        choosePopUpItem("bar", in: shows)

        let row = app.staticTexts["attribute.brakePressureFront"]
        XCTAssertTrue(
            text(of: row).contains("kPa → bar"), "The row does not report the conversion: \(text(of: row))")
    }

    /// A channel the file names itself is a source to map to, never a row of its own (#191).
    @MainActor
    func testASourceChannelIsNotListedAsAnAttribute() throws {
        launch()
        testing("Add Fixture Data (Noisy CAN)")
        XCTAssertTrue(sidebarInput("racechrono-v3-noisy").waitForExistence(timeout: Self.timeout))
        sidebarInput("racechrono-v3-noisy").click()

        let showAll = app.descendants(matching: .any).matching(identifier: "attributes.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout))
        reveal(showAll)
        showAll.click()
        XCTAssertFalse(
            app.staticTexts["attribute.canbus:analog_1"].exists,
            "One logger's wiring is listed as though it were part of the vocabulary")
        XCTAssertFalse(app.staticTexts["attribute.canbus:brake_pressure_front"].exists)
    }

}
