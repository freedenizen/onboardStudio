import XCTest

// ci-shard: 1
/// J60: put the Logbook right (#454). Several sessions are selected at once, removed with no
/// question and brought back by Edit ▸ Undo; a session on the wrong day is moved by its right-click
/// menu or by dragging it onto a day in the sidebar.
final class LogbookCorrectionsUITests: OnboardStudioUITestCase {
    /// The rows of the Logbook's table of sessions.
    private var rows: XCUIElementQuery {
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        return table.descendants(matching: .any).matching(rowTypes)
    }

    private func row(_ index: Int) -> XCUIElement { rows.element(boundBy: index) }

    /// Near the row's left end: its frame spans every column, those scrolled out of view too, so
    /// its middle can be outside the table.
    private func start(of index: Int) -> XCUICoordinate {
        row(index).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
    }

    /// Waits until the table lists `count` sessions.
    @MainActor
    private func expectRows(_ count: Int, _ message: String, file: StaticString = #filePath, line: UInt = #line) {
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", count), object: rows)
        XCTAssertEqual(
            XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "\(message): \(rows.count)",
            file: file, line: line)
    }

    /// The menu item called `title` that is on screen: a context menu's items share their titles
    /// with the menu bar's, which are always in the accessibility tree.
    @MainActor
    private func visibleMenuItem(_ title: String) -> XCUIElement? {
        let items = app.menuItems.matching(NSPredicate(format: "title == %@", title))
        let deadline = Date().addingTimeInterval(Self.timeout)
        while Date() < deadline {
            if let item = items.allElementsBoundByIndex.first(where: \.isHittable) { return item }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        return nil
    }

    /// The fixtures into an empty logbook, every file on its own day.
    @MainActor
    private func addTheFixtures() {
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        XCTAssertTrue(row(0).waitForExistence(timeout: Self.timeout), "No sessions listed")
    }

    /// Three sessions selected with a shift-click are taken out by the detail's button, and Undo and
    /// Redo, named for it, take it back and do it again.
    @MainActor
    func testSeveralSessionsAreRemovedAndUndone() throws {
        launch(logbook: true)
        addTheFixtures()
        let count = rows.count
        start(of: 0).click()
        XCUIElement.perform(withKeyModifiers: .shift) { start(of: 2).click() }
        let title = app.staticTexts["logbook.selection.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "No detail for the selection")
        expect(title, toRead: "3 Sessions Selected")

        app.buttons["logbook.selection.remove"].click()
        expectRows(count - 3, "The sessions were not removed")
        XCTAssertFalse(app.sheets.firstMatch.exists, "A removal asked first")
        menu("Edit", "Undo Remove 3 Sessions")
        expectRows(count, "Undo did not bring them back")
        menu("Edit", "Redo Remove 3 Sessions")
        expectRows(count - 3, "Redo did not remove them again")
        app.typeKey("z", modifierFlags: .command)
        expectRows(count, "⌘Z did not bring them back")
    }

    /// A day begun, the fixtures put on it, and a second day at Sonoma: a session moves from the
    /// first to the second by its right-click menu — undone — and then by a drag.
    @MainActor
    func testASessionIsMovedByItsMenuAndByADrag() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        let today = Date().formatted(date: .abbreviated, time: .omitted)
        app.buttons["logbook.newTrackDay"].click()
        let create = app.buttons["trackday.new.create"]
        XCTAssertTrue(create.waitForExistence(timeout: Self.timeout), "No New Track Day sheet")
        create.click()
        testing("Add Fixture Sessions to Selected Day")
        _ = finishAddingToDay(.thisDay)
        XCTAssertTrue(row(0).waitForExistence(timeout: Self.timeout), "No sessions on the day")

        app.buttons["logbook.newTrackDay"].click()
        let search = app.textFields["trackday.new.circuit"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "No New Track Day sheet")
        search.click()
        search.typeText("Sonoma")
        let match = app.descendants(matching: .any).matching(identifier: "trackday.new.match.Sonoma Raceway").firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: Self.timeout), "The catalogue did not offer Sonoma")
        match.click()
        create.click()
        let sonoma = app.staticTexts["logbook.day.\(today) · Sonoma Raceway"]
        XCTAssertTrue(sonoma.waitForExistence(timeout: Self.timeout), "No second day in the sidebar")

        let first = app.staticTexts["logbook.day.\(today) · Track day"]
        first.click()
        XCTAssertTrue(row(0).waitForExistence(timeout: Self.timeout), "The first day lost its sessions")
        let count = rows.count

        // By the right-click menu.
        start(of: 0).rightClick()
        let moveTo = try XCTUnwrap(visibleMenuItem("Move to Day"), "No Move to Day in the row's menu")
        moveTo.hover()
        let target = try XCTUnwrap(visibleMenuItem("\(today) · Sonoma Raceway"), "Sonoma's day is not offered")
        target.click()
        expectRows(count - 1, "The session did not leave the day")
        menu("Edit", "Undo Move Session")
        expectRows(count, "Undo did not bring the session back")

        // By a drag onto the day in the sidebar.
        start(of: 0).click(
            forDuration: 0.6, thenDragTo: sonoma.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        expectRows(count - 1, "The dragged session did not leave the day")
        sonoma.click()
        expectRows(1, "The session is not on Sonoma's day")
    }
}
