import XCTest

// ci-shard: 1
/// #464: with nothing chosen a RaceChrono project's speedometer read metres per second, and the
/// Logbook read km/h whatever Settings said. Speed is now in the unit chosen, else the file's own
/// mph or km/h, else the region's.
final class SpeedUnitUITests: OnboardStudioUITestCase {
    /// Settings ▸ Units ▸ Speed is mph: the Logbook's top speed is in mph, not the km/h it was
    /// written in whatever the setting.
    @MainActor
    func testTheLogbookShowsSpeedInTheUnitChosenInSettings() throws {
        launch(logbook: true, extraArguments: ["-speedUnit", "mph"])
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout))
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()

        // The first session with a top speed to show: not every fixture has a speed channel.
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 3"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "No sessions listed")
        let topSpeed = app.staticTexts["logbook.detail.topSpeed"]
        var found = false
        for index in 0..<min(rows.count, 10) where !found {
            rows.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
            XCTAssertTrue(sessionNewProject.waitForExistence(timeout: Self.timeout))
            found = topSpeed.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(found, "No session shows a top speed")
        XCTAssertTrue(text(of: topSpeed).hasSuffix(" mph"), text(of: topSpeed))
    }

    /// A file that records metres per second, in a region whose roads are signed in kilometres:
    /// a new speedometer reads km/h, and its inspector says where that came from.
    @MainActor
    func testASpeedometerOnMetresPerSecondDataReadsTheRegionsUnit() throws {
        launch(extraArguments: [
            "-speedUnit", "automatic", "-AppleLocale", "de_DE", "-AppleMeasurementUnits", "Centimeters",
            "-AppleMetricUnits", "YES",
        ])
        testing("Add Fixture Data (RaceChrono)")
        XCTAssertTrue(sidebarInput("racechrono-v3").waitForExistence(timeout: Self.timeout), "Data not listed")
        toolbarMenu("toolbar.addObject", "Speedometer")
        XCTAssertTrue(sidebarObject("Speedometer").waitForExistence(timeout: Self.timeout))
        let resolved = app.staticTexts["object.speedUnitResolved"]
        XCTAssertTrue(resolved.waitForExistence(timeout: Self.timeout), "The picker does not say what Automatic is")
        expect(resolved, toRead: "Showing kph for your region, as the data is in m/s.")
    }
}
