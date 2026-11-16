import XCTest

// ci-shard: 5
/// J78: see how much of the car's grip was used (#558). A session's details read its best lap
/// against the grip the car has shown in conditions like these; the car's card says what that
/// grip is and lets the driver adjust it.
final class GripUITests: OnboardStudioUITestCase {
    @MainActor
    func testASessionsGripIsReadAgainstTheCars() throws {
        launch(logbook: true)
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
        let grip = app.descendants(matching: .any).matching(identifier: "logbook.detail.grip").firstMatch
        XCTAssertTrue(grip.waitForExistence(timeout: Self.timeout * 2), "No grip in the session's details")
        XCTAssertTrue(text(of: grip).contains("of the grip braking and turning"), text(of: grip))
        XCTAssertTrue(text(of: grip).contains("Against"), text(of: grip))

        // The car's card: what it has shown, and the driver's scale on it, a step of Undo.
        let sidebar = app.outlines.firstMatch
        sidebar.staticTexts["Test Car"].click()
        let row = app.descendants(matching: .any).matching(identifier: "car.header.grip").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No grip on the car's card")
        let stepper = app.steppers["car.header.gripAdjustment"]
        XCTAssertTrue(stepper.exists, "No grip adjustment")
        stepper.incrementArrows.firstMatch.click()
        XCTAssertTrue(
            app.menuBarItems["Edit"].menus.menuItems["Undo Adjust Grip"].waitForExistence(timeout: Self.timeout),
            "The adjustment is not a step of Undo")
    }
}
