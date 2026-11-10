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
        // Each row is named once: the hint is inside the field, not a second label beside the
        // row's own (#457: "Car · What you drove", "Circuit · Search circuits").
        XCTAssertFalse(app.staticTexts["Search circuits"].exists, "The circuit row has a second label")
        XCTAssertFalse(app.staticTexts["What you drove"].exists, "The car row has a second label")
        XCTAssertEqual(search.placeholderValue, "Search circuits")
        XCTAssertEqual(app.textFields["trackday.new.car"].placeholderValue, "What you drove")
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
        // Most are dated some other day, so the sheet asks before it files those (#456); a logger
        // with a wrong clock is why the day chosen may still be the answer.
        testing("Add Fixture Sessions to Selected Day")
        let question = app.staticTexts["trackday.strays.question"]
        XCTAssertTrue(question.waitForExistence(timeout: Self.timeout * 3), "No question about the other days' files")
        XCTAssertTrue(text(of: question).contains("not from \(dayLabel(for: "Sonoma Raceway"))"), text(of: question))
        XCTAssertFalse(app.staticTexts["trackday.summary"].exists, "Summed up before the answer")
        let summary = finishAddingToDay(.thisDay)
        XCTAssertFalse(summary.contains("own day"), summary)
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 8"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "No sessions under the day")
        XCTAssertFalse(app.staticTexts["trackday.header.empty"].exists)
        // The sessions took the day's car.
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(sessionNewProject.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'Miata'")).firstMatch.exists)
    }

    /// #456: the files that are not the day's go on the days they say, when that is the answer —
    /// the day chosen keeps only what could be its own, and the logbook gains the other days.
    @MainActor
    func testFilesOfOtherDaysGoOnTheirOwnDaysWhenToldTo() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout))
        app.buttons["logbook.newTrackDay"].click()
        let search = app.textFields["trackday.new.circuit"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "No New Track Day sheet")
        search.click()
        search.typeText("Sonoma")
        let match = app.descendants(matching: .any).matching(identifier: "trackday.new.match.Sonoma Raceway").firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: Self.timeout), "The catalogue did not offer Sonoma")
        match.click()
        app.buttons["trackday.new.create"].click()
        XCTAssertTrue(app.staticTexts["trackday.header.title"].waitForExistence(timeout: Self.timeout))

        testing("Add Fixture Sessions to Selected Day")
        let summary = finishAddingToDay(.ownDays)
        XCTAssertTrue(summary.contains("on their own days"), summary)

        // The day keeps the files with no date and no circuit of their own; the rest are under days
        // of their own. The logbook now spans several years, so the sidebar folds its days under
        // them — and the year of the day being worked on is open, its row still there (#485).
        let onTheDay = rows.count
        XCTAssertGreaterThan(onTheDay, 0, "Nothing stayed on the day")
        let chosen = app.staticTexts["logbook.day.\(dayLabel(for: "Sonoma Raceway"))"]
        XCTAssertTrue(chosen.waitForExistence(timeout: Self.timeout), "The chosen day is folded out of sight")
        let days = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'logbook.day.'"))
        XCTAssertGreaterThan(days.count, 1, "No days were made for the files of other days")
        app.staticTexts["logbook.scope.all"].click()
        let more = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > %d", onTheDay), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [more], timeout: Self.timeout), .completed, "Only the day's sessions")
    }

    /// The rows of the Logbook's table of sessions.
    private var rows: XCUIElementQuery {
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        return table.descendants(matching: .any).matching(rowTypes)
    }

    /// "4 Nov 2026 · Sonoma Raceway": today's date, as the sidebar labels a day begun today.
    private func dayLabel(for circuit: String) -> String {
        "\(Date().formatted(date: .abbreviated, time: .omitted)) · \(circuit)"
    }
}
