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
        let inputs = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'input.'"))
        let inputsBefore = inputs.count
        addToProject.click()
        let added = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count > %d", inputsBefore), object: inputs)
        XCTAssertEqual(XCTWaiter().wait(for: [added], timeout: Self.timeout), .completed, "Nothing added")
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
            ("logbook.remove", "Remove from Logbook…"),
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
