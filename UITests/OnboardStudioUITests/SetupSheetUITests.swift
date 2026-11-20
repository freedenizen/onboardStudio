import XCTest

// ci-shard: 6
/// J75: note what was on the car (#559). A session's setup sheet takes pressures at each corner,
/// is kept with the car as a named setup, and a car's starting setup is what its next session has.
final class SetupSheetUITests: OnboardStudioUITestCase {
    @MainActor
    func testASetupIsNotedSavedToTheCarAndUndone() throws {
        launch(logbook: true, extraArguments: ["-setupPressureUnit", "psi"])
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Session at a Circuit")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        let car = app.textFields["trackday.car"]
        if car.waitForExistence(timeout: Self.timeout) {
            car.click()
            car.typeText("Test Car")
            app.buttons["trackday.car.setButton"].click()
        }
        app.buttons["trackday.done"].click()

        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        let edit = app.buttons["logbook.editSetup"]
        XCTAssertTrue(edit.waitForExistence(timeout: Self.timeout), "No Edit Setup… in the session's conditions")
        reveal(edit)
        edit.click()
        let name = app.textFields["setup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.timeout), "No setup sheet")
        name.click()
        name.typeText("Base")
        for (corner, value) in [("Front Left", "30"), ("Front Right", "30"), ("Rear Left", "28"), ("Rear Right", "28")]
        {
            let field = app.textFields["setup.Cold Pressure, \(corner)"]
            field.click()
            field.typeText(value)
        }
        let save = app.buttons["setup.saveToCar"]
        XCTAssertTrue(save.isEnabled, "Save to Car is not offered for a named setup in a car")
        save.click()
        let starting = app.checkBoxes["setup.starting"]
        XCTAssertTrue(starting.waitForExistence(timeout: Self.timeout), "Not kept with the car")
        starting.click()
        app.buttons["setup.done"].click()

        let summary = app.staticTexts["logbook.setupSummary"]
        let noted = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "value CONTAINS 'Base · 30/28 psi cold' OR label CONTAINS 'Base · 30/28 psi cold'"),
            object: summary)
        XCTAssertEqual(XCTWaiter().wait(for: [noted], timeout: Self.timeout), .completed, text(of: summary))

        // One step of Undo, named for what it was.
        XCTAssertTrue(
            app.menuBarItems["Edit"].menus.menuItems["Undo Change Setup"].exists,
            "The sheet's values are not one step of Undo")
        menu("Edit", "Undo Change Setup")
        menu("Edit", "Undo Make Starting Setup")
        menu("Edit", "Undo Save Setup")
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS 'Not noted' OR label CONTAINS 'Not noted'"), object: summary)
        XCTAssertEqual(XCTWaiter().wait(for: [cleared], timeout: Self.timeout), .completed, text(of: summary))
    }
}
