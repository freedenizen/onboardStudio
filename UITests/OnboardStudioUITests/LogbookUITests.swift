import AppKit
import XCTest

// ci-shard: 1
/// J38: every track day in one place — the Logbook window lists the sessions, narrows them by
/// circuit, car, year or a search, and takes one into the open project (#347).
final class LogbookUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheLogbookListsSessionsAndAddsOneToTheProject() throws {
        launch()
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        // A SwiftUI table's rows read as table rows or outline rows depending on the backing view.
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 3"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "No sessions listed")
        let total = rows.count

        // A search narrows the table; clearing it brings everything back.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "No search field")
        search.click()
        search.typeText("racechrono")
        let narrowed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count < %d AND count > 0", total), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [narrowed], timeout: Self.timeout), .completed, "Search did nothing")
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        let restored = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", total), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [restored], timeout: Self.timeout), .completed)

        // Selecting a session shows its laps and offers the way into the project.
        // The row is wider than the window's visible part; a point near its left edge is on screen.
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let addToProject = app.buttons["logbook.addToProject"]
        XCTAssertTrue(addToProject.waitForExistence(timeout: Self.timeout), "No detail for the selected session")
        XCTAssertTrue(sessionNewProject.exists)
        assertTheSessionsActionsAreInViewAndInFull()
        assertASessionOutOfTheTableHasNoDetail(search: search, action: addToProject)
        let inputs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'input.'"))
        let inputsBefore = inputs.count
        addToProject.click()
        let added = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > %d", inputsBefore), object: inputs)
        XCTAssertEqual(XCTWaiter().wait(for: [added], timeout: Self.timeout), .completed, "Nothing added")
    }

    /// #498: a session added before the first lap was corrected (#477) kept the laps it was read
    /// with. The Logbook says so above the table and reads the file again when asked: the first
    /// lap, called partial, is the whole lap it was.
    @MainActor
    func testASessionReadBeforeTheLapFixIsReadAgainOnRequest() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout))
        testing("Add Fixture Session Read Before the Lap Fix")
        let offer = app.staticTexts["logbook.lapReading.text"]
        XCTAssertTrue(offer.waitForExistence(timeout: Self.timeout * 3), "Nothing offers to read the session again")
        expect(offer, toRead: "1 session here was read before a correction to the first lap.")

        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "The session is not listed")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let laps = app.staticTexts["logbook.detail.laps"]
        XCTAssertTrue(laps.waitForExistence(timeout: Self.timeout), "No detail for the session")
        expect(laps, toRead: "0 complete of 2")

        let read = app.buttons["logbook.lapReading.read"]
        XCTAssertEqual(read.label, "Read It Again")
        read.click()
        expect(laps, toRead: "1 complete of 2")
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: offer)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: Self.timeout), .completed, "Still offered once read")
    }

    /// A search that finds nothing says so, and a session the search or the sidebar has taken out
    /// of the table has no detail left on screen with its buttons live (#457). It comes back with
    /// the session.
    @MainActor
    private func assertASessionOutOfTheTableHasNoDetail(search: XCUIElement, action: XCUIElement) {
        search.click()
        search.typeText("zzzz")
        let noResults = app.staticTexts.matching(
            NSPredicate(format: "value BEGINSWITH 'No Results' OR label BEGINSWITH 'No Results'")
        ).firstMatch
        XCTAssertTrue(noResults.waitForExistence(timeout: Self.timeout), "An empty search shows an empty table")
        XCTAssertTrue(action.waitForNonExistence(timeout: Self.timeout), "The detail is of a session the search hid")
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(action.waitForExistence(timeout: Self.timeout), "The detail did not come back with the session")

        // The newest session is at the circuit the fixtures call Sonoma; another circuit's sessions
        // do not include it.
        let sidebar = app.descendants(matching: .any).matching(identifier: "logbook.sidebar").firstMatch
        let other = sidebar.staticTexts["Test Circuit"]
        XCTAssertTrue(other.waitForExistence(timeout: Self.timeout), "No Test Circuit in the sidebar")
        other.click()
        XCTAssertTrue(action.waitForNonExistence(timeout: Self.timeout), "The detail is of another circuit's session")
        sidebar.staticTexts["logbook.scope.all"].click()
        XCTAssertTrue(action.waitForExistence(timeout: Self.timeout), "The detail did not come back with All Sessions")
    }

    /// The ways out of a session are under its detail, not at the end of it, and wrap onto another
    /// row rather than shorten: each is inside the window without scrolling, and at least as wide
    /// as its own title (#448: they read "C…", "Re…" and "Ex…", below the fold).
    @MainActor
    private func assertTheSessionsActionsAreInViewAndInFull() {
        let window = app.windows["Logbook"]
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize(for: .small))
        let actions = [
            ("logbook.open", "New Project"), ("logbook.addToProject", "Add to Current Project"),
            ("logbook.coach", "Coach…"), ("logbook.replay", "Replay…"), ("logbook.compareWith", "Compare With"),
            ("logbook.debrief", "Export Coaching Debrief…"), ("logbook.showInFinder", "Show in Finder"),
            ("logbook.remove", "Remove from Logbook"),
        ]
        for (identifier, title) in actions {
            let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(control.exists, "\(title) is missing")
            XCTAssertTrue(window.frame.contains(control.frame), "\(title) is out of view at \(control.frame)")
            let titleWidth = (title as NSString).size(withAttributes: [.font: font]).width
            XCTAssertGreaterThan(control.frame.width, titleWidth, "\(title) is cut short")
        }
    }
}
