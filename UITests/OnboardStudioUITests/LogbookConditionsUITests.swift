import XCTest

// ci-shard: 2
/// J39: record a session's conditions — weather, track, air, tyres, setup and notes, kept with
/// the entry and shown in the table (#348).
final class LogbookConditionsUITests: OnboardStudioUITestCase {
    @MainActor
    func testConditionsAreKeptWithTheSession() throws {
        launch()
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "No sessions listed")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        // Weather from a pop-up, tyres as text committed with Return.
        let weather = app.popUpButtons["logbook.weather"]
        XCTAssertTrue(weather.waitForExistence(timeout: Self.timeout), "No conditions editor")
        choosePopUpItem("Sunny", in: weather)
        let tyres = app.textFields["logbook.tyres"]
        tyres.click()
        tyres.typeText("RE-71RS\n")
        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", "Sunny"), object: weather)
        XCTAssertEqual(
            XCTWaiter().wait(for: [saved], timeout: Self.timeout), .completed, weather.value as? String ?? "")

        // The table's Conditions column says so, and it survives closing and reopening the window.
        let summary = app.staticTexts["Sunny · RE-71RS"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout), "The table does not show the conditions")
        app.typeKey("w", modifierFlags: .command)
        menu("Window", "Logbook")
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["Sunny · RE-71RS"].waitForExistence(timeout: Self.timeout), "Not kept")
    }
}
