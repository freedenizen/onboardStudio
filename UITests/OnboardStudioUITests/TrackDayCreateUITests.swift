import XCTest

// ci-shard: 2
/// J47: a track day begins in the logbook — the date, the circuit, the car — and its sessions
/// are added under it (#393).
final class TrackDayCreateUITests: OnboardStudioUITestCase {
    @MainActor
    func testADayIsBegunAndItsSessionsAddedUnderIt() throws {
        launch()
        menu("Window", "Logbook")
        let newDay = app.buttons["logbook.newTrackDay"]
        XCTAssertTrue(newDay.waitForExistence(timeout: Self.timeout), "No New Track Day… in the toolbar")
        newDay.click()

        // The sheet: a circuit from the catalogue, a car typed, Create.
        let search = app.textFields["trackday.new.circuit"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "No New Track Day sheet")
        search.click()
        search.typeText("Sonoma")
        // Link-style buttons read as links, so the match is found by identifier alone.
        let match = app.descendants(matching: .any).matching(identifier: "trackday.new.match.Sonoma Raceway").firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: Self.timeout), "The catalogue did not offer Sonoma")
        match.click()
        XCTAssertTrue(app.staticTexts["trackday.new.circuit.chosen"].waitForExistence(timeout: Self.timeout))
        let car = app.textFields["trackday.new.car"]
        car.click()
        car.typeText("Miata")
        app.buttons["trackday.new.create"].click()

        // The day is chosen in the sidebar and shown above an empty table.
        let title = app.staticTexts["trackday.header.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "No day header")
        expect(title, toRead: "Sonoma Raceway")
        XCTAssertTrue(app.staticTexts["trackday.header.empty"].exists, "An empty day says so")
        XCTAssertEqual(app.textFields["trackday.header.car"].value as? String, "Miata")
        XCTAssertTrue(app.staticTexts["logbook.day.\(dayLabel(for: "Sonoma Raceway"))"].exists, "Not in the sidebar")

        // Sessions under it: the fixtures, through the hook that stands in for the open panel.
        testing("Add Fixture Sessions to Selected Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Sessions sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 3"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "No sessions under the day")
        XCTAssertFalse(app.staticTexts["trackday.header.empty"].exists)
        // The sessions took the day's car.
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(app.buttons["logbook.open"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Miata'")).firstMatch.exists)
    }

    /// "4 Nov 2026 · Sonoma Raceway": today's date, as the sidebar labels a day begun today.
    private func dayLabel(for circuit: String) -> String {
        "\(Date().formatted(date: .abbreviated, time: .omitted)) · \(circuit)"
    }
}
