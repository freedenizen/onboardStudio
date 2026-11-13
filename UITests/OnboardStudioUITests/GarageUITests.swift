import XCTest

// ci-shard: 1
/// J59: say what was driven, and keep the garage (#489, #490). A first import asks for the car in
/// its report; the car is then a row of the Logbook's sidebar, with its notes and the corrections
/// its name may need.
final class GarageUITests: OnboardStudioUITestCase {
    private var sidebar: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "logbook.sidebar").firstMatch
    }
    private var title: XCUIElement { app.staticTexts["car.header.title"] }
    private var subtitle: XCUIElement { app.staticTexts["car.header.subtitle"] }
    private var notes: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "car.header.notes").firstMatch
    }

    /// The rows of the Logbook's table of sessions.
    private var rows: XCUIElementQuery {
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        return table.descendants(matching: .any).matching(rowTypes)
    }

    /// The fixtures into an empty logbook, with no day chosen, and "Test Car" given in the report.
    @MainActor
    private func addTheFixturesInTestCar() {
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        let question = app.descendants(matching: .any).matching(identifier: "trackday.car.question").firstMatch
        XCTAssertTrue(question.waitForExistence(timeout: Self.timeout), "The report does not ask for the car")
        XCTAssertTrue(text(of: question).contains("No car is set for the "), text(of: question))
        let field = app.textFields["trackday.car"]
        field.click()
        field.typeText("Test Car")
        app.buttons["trackday.car.setButton"].click()
        let done = app.descendants(matching: .any).matching(identifier: "trackday.car.set").firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "The report does not say the car was set")
        expect(done, toContain: "Test Car is the car of the ")
        app.buttons["trackday.done"].click()
        XCTAssertTrue(sidebar.staticTexts["Test Car"].waitForExistence(timeout: Self.timeout), "No Test Car")
        XCTAssertFalse(sidebar.staticTexts["No car"].exists, "Sessions were left with no car")
    }

    /// The report asks; the car's row shows what the logbook holds of it, keeps its notes, and a
    /// rename reaches every session.
    @MainActor
    func testAFirstImportAsksForTheCarAndTheGarageShowsIt() throws {
        launch(logbook: true)
        addTheFixturesInTestCar()

        sidebar.staticTexts["Test Car"].click()
        expect(title, toRead: "Test Car")
        expect(subtitle, toContain: "sessions on")
        XCTAssertFalse(app.buttons["car.header.remove"].isEnabled, "A car that is driven can be removed")
        XCTAssertTrue(notes.waitForExistence(timeout: Self.timeout), "No notes for the car")
        notes.click()
        notes.typeText("Soft springs\n")
        sidebar.staticTexts["logbook.scope.all"].click()
        XCTAssertTrue(title.waitForNonExistence(timeout: Self.timeout), "The car header stayed for All Sessions")
        sidebar.staticTexts["Test Car"].click()
        expect(notes, toRead: "Soft springs")

        app.buttons["car.header.rename"].click()
        let name = app.textFields["car.rename.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.timeout), "No Rename sheet")
        name.typeKey("a", modifierFlags: .command)
        name.typeText("Club Car")
        expect(app.staticTexts["car.rename.explanation"], toContain: "sessions, and in the garage")
        app.buttons["car.rename.confirm"].click()
        expect(title, toRead: "Club Car")
        XCTAssertTrue(sidebar.staticTexts["Club Car"].waitForExistence(timeout: Self.timeout), "No Club Car")
        XCTAssertFalse(sidebar.staticTexts["Test Car"].exists, "Sessions were left under the old name")
        expect(notes, toRead: "Soft springs")
    }

    /// Replaces what the field holds and commits it.
    @MainActor
    private func retype(_ field: XCUIElement, _ text: String) {
        field.click()
        field.typeKey("a", modifierFlags: .command)
        field.typeText("\(text)\n")
        expect(field, toRead: text)
    }

    /// A misspelling put right on the session leaves the garage with it. A car with notes stays
    /// when nothing names it any more, listed with no sessions, until it is removed — which Edit ▸
    /// Undo takes back.
    @MainActor
    func testACarNothingNamesIsTidiedOrRemoved() throws {
        launch(logbook: true)
        addTheFixturesInTestCar()

        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let sessionCar = app.textFields["logbook.detail.car"]
        XCTAssertTrue(sessionCar.waitForExistence(timeout: Self.timeout), "A session has no Car field")
        retype(sessionCar, "Tset Car")
        let typo = sidebar.staticTexts["Tset Car"]
        XCTAssertTrue(typo.waitForExistence(timeout: Self.timeout), "No Tset Car")
        retype(sessionCar, "Test Car")
        XCTAssertTrue(typo.waitForNonExistence(timeout: Self.timeout), "A misspelling put right stayed in the garage")

        retype(sessionCar, "Loan Car")
        let loan = sidebar.staticTexts["Loan Car"]
        XCTAssertTrue(loan.waitForExistence(timeout: Self.timeout), "No Loan Car")
        loan.click()
        expect(subtitle, toContain: "1 session on 1 day")
        XCTAssertTrue(notes.waitForExistence(timeout: Self.timeout), "No notes for the car")
        notes.click()
        notes.typeText("Borrowed for a day\n")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(sessionCar.waitForExistence(timeout: Self.timeout), "The Loan Car session has no Car field")
        sessionCar.click()
        sessionCar.typeKey("a", modifierFlags: .command)
        sessionCar.typeText("Test Car\n")

        expect(subtitle, toRead: "In the garage; no day or session names it.")
        XCTAssertTrue(loan.exists, "A car with notes left the garage by itself")
        XCTAssertTrue(app.staticTexts["No Sessions in This Car"].exists, "No word on why the table is empty")
        expect(notes, toRead: "Borrowed for a day")
        let remove = app.buttons["car.header.remove"]
        XCTAssertTrue(remove.isEnabled)
        // No question: Edit ▸ Undo brings it back, notes and all (#454).
        remove.click()
        XCTAssertTrue(loan.waitForNonExistence(timeout: Self.timeout), "The car is still listed")
        XCTAssertTrue(sidebar.staticTexts["Test Car"].exists)
        menu("Edit", "Undo Remove from Garage")
        XCTAssertTrue(loan.waitForExistence(timeout: Self.timeout), "Undo did not bring the car back")
        loan.click()
        expect(notes, toRead: "Borrowed for a day")
    }
}
