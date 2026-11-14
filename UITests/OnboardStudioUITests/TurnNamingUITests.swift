import XCTest

// ci-shard: 4
/// J66: name a circuit's turns from its card in the Logbook (#550). The sheet draws the circuit
/// from the best lap there with a field for each corner; a name typed there is kept for the
/// circuit, and Edit ▸ Undo Name Turns takes it back.
final class TurnNamingUITests: OnboardStudioUITestCase {
    private var sidebar: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "logbook.sidebar").firstMatch
    }

    private func field(_ number: Int) -> XCUIElement { app.textFields["turns.name.\(number)"] }

    /// Opens the sheet from the card and waits for the lap to be read.
    @MainActor
    private func openTheSheet() {
        app.buttons["circuit.card.nameTurns"].click()
        XCTAssertTrue(field(1).waitForExistence(timeout: Self.timeout * 2), "The sheet has no field for corner 1")
        XCTAssertTrue(app.descendants(matching: .any)["turns.map"].exists, "The sheet draws no map")
    }

    @MainActor
    func testATurnNamedOnTheCardIsKeptForTheCircuitUntilUndone() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        app.buttons["trackday.done"].click()
        // The synthetic laps placed at the catalogue's Thunderhill: two corners, counted 1 and 2.
        let circuit = sidebar.staticTexts["Thunderhill Raceway Park"]
        XCTAssertTrue(circuit.waitForExistence(timeout: Self.timeout), "No Thunderhill under Circuits")
        circuit.click()

        openTheSheet()
        expect(field(1), toRead: "1")
        expect(field(2), toRead: "2")
        field(2).click()
        field(2).typeKey("a", modifierFlags: .command)
        field(2).typeText("3a")
        app.buttons["turns.done"].click()
        XCTAssertTrue(field(1).waitForNonExistence(timeout: Self.timeout), "Done left the sheet up")

        openTheSheet()
        expect(field(2), toRead: "3a")
        app.buttons["turns.cancel"].click()
        XCTAssertTrue(field(1).waitForNonExistence(timeout: Self.timeout), "Cancel left the sheet up")

        menu("Edit", "Undo Name Turns")
        openTheSheet()
        expect(field(2), toRead: "2")
        app.buttons["turns.cancel"].click()
    }
}
