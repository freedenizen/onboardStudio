import XCTest

// ci-shard: 4
/// J38: the Logbook is three columns, as Mail is (#503) — the sidebar, the sessions and the session
/// chosen. The toolbar follows the columns, so no button sits across the session's edge however
/// wide it is dragged, and the personal-best star leads the table, so a narrow table keeps it.
final class LogbookColumnsUITests: OnboardStudioUITestCase {
    private var window: XCUIElement { app.windows["Logbook"] }
    private var table: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
    }
    private var detail: XCUIElement { app.staticTexts["logbook.detail.laps"] }

    /// The session's left edge: the split view's divider furthest to the right.
    private var edge: XCUIElement {
        window.splitters.allElementsBoundByIndex.max { $0.frame.midX < $1.frame.midX } ?? window.splitters.firstMatch
    }

    @MainActor
    func testTheToolbarFollowsTheColumnsAndTheStarLeads() throws {
        launch(logbook: true)
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        let rows = table.descendants(matching: .any).matching(
            NSPredicate(
                format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
                XCUIElement.ElementType.outlineRow.rawValue))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No sessions listed")
        // Near the row's leading edge: on CI's 1,024-point screen the table scrolls sideways, and the
        // middle of a row lies outside the column it is in.
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "No detail for the selected session")

        try expectTheToolbarToFollow("at the session's narrowest")
        try expectTheStarFirstAndInView("at the session's narrowest")

        let grab = edge.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        grab.click(forDuration: 0.3, thenDragTo: grab.withOffset(CGVector(dx: -300, dy: 0)))
        try expectTheToolbarToFollow("at the session's widest")
        try expectTheStarFirstAndInView("at the session's widest")
    }

    /// No control in the toolbar runs across the session's edge; New Project is over the session
    /// and the list's buttons over the list.
    @MainActor
    private func expectTheToolbarToFollow(_ when: String) throws {
        let line = edge.frame.midX
        let controls = window.toolbars.firstMatch.descendants(matching: .any).allElementsBoundByIndex.filter {
            [.button, .menuButton, .popUpButton, .radioButton, .searchField].contains($0.elementType)
                && $0.frame.width > 0
        }
        XCTAssertFalse(controls.isEmpty, "\(when): no toolbar controls found")
        for control in controls {
            let name = control.identifier.isEmpty ? control.label : control.identifier
            XCTAssertFalse(
                control.frame.minX < line && control.frame.maxX > line,
                "\(when): \(name) runs across the session's edge at \(line): \(control.frame)")
        }
        let newProject = app.menuButtons["logbook.newProject"]
        XCTAssertTrue(newProject.exists, "No New Project in the toolbar")
        XCTAssertGreaterThan(newProject.frame.minX, line, "\(when): New Project is not over the session")
        // A narrow window's toolbar puts what does not fit in its overflow menu; whatever of the
        // list's buttons is shown is over the list.
        let list = ["logbook.newTrackDay", "logbook.addTrackDay", "logbook.transfer", "logbook.view"].compactMap {
            identifier in controls.first { $0.identifier == identifier }
        }
        XCTAssertFalse(list.isEmpty, "\(when): none of the list's controls is in the toolbar")
        for control in list {
            XCTAssertLessThan(control.frame.maxX, line, "\(when): \(control.identifier) is not over the list")
        }
    }

    /// PB is the table's first column, and all of it is in view.
    @MainActor
    private func expectTheStarFirstAndInView(_ when: String) throws {
        let headers = table.descendants(matching: .button).allElementsBoundByIndex
            .filter { $0.frame.width > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }
        let first = try XCTUnwrap(headers.first, "\(when): the table has no column headers")
        XCTAssertEqual(first.title.isEmpty ? first.label : first.title, "PB", "\(when): PB is not the first column")
        XCTAssertTrue(
            table.frame.contains(first.frame), "\(when): PB is not all in view: \(first.frame) in \(table.frame)")
    }
}
