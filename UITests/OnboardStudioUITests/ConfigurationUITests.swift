import XCTest

// ci-shard: 4
/// J65: say which configuration of a circuit a session drove (#549). A session filed under the club
/// course is its own row under Circuits, with its own best, Trends, goals and plan, and Edit ▸ Undo
/// puts it back on the circuit's usual layout.
final class ConfigurationUITests: OnboardStudioUITestCase {
    private var sidebar: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "logbook.sidebar").firstMatch
    }

    /// The rows of the Logbook's table of sessions.
    private var rows: XCUIElementQuery {
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        return table.descendants(matching: .any).matching(rowTypes)
    }

    @MainActor
    func testASessionOnTheClubCourseIsItsOwnCircuitUntilUndone() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        app.buttons["trackday.done"].click()

        // The first session at a circuit: a configuration is a layout of one.
        let field = app.textFields["logbook.detail.configuration"]
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No sessions")
        for index in 0..<rows.count where !field.exists {
            rows.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
            _ = field.waitForExistence(timeout: 2)
        }
        XCTAssertTrue(field.exists, "No session at a circuit has a Configuration field")
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("Club Course\n")
        expect(field, toRead: "Club Course")

        let club = sidebar.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " — Club Course")).firstMatch
        XCTAssertTrue(club.waitForExistence(timeout: Self.timeout), "The club course is not a circuit of its own")
        menu("Edit", "Undo Change Configuration")
        XCTAssertTrue(club.waitForNonExistence(timeout: Self.timeout), "Undo left the session on the club course")
    }
}
