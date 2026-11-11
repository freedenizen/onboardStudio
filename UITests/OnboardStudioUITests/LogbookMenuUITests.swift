import XCTest

// ci-shard: 1
/// J55: the Logbook from the menu bar and the keyboard (#450). With the Logbook in front, the
/// Session menu acts on the session whose detail is on show, ⌘1–⌘3 switch its views and ⌘F finds;
/// the editor's menus are dimmed and leave their keys to the Logbook.
final class LogbookMenuUITests: OnboardStudioUITestCase {
    private var rows: XCUIElementQuery {
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        return table.descendants(matching: .any).matching(rowTypes)
    }

    /// Something only a session's detail has.
    private var detail: XCUIElement { app.staticTexts["logbook.detail.laps"] }

    private var removeConfirmation: XCUIElement { app.windows.buttons["Remove from Logbook"] }

    /// The Logbook at launch, the fixture day added and its first session selected.
    @MainActor
    private func selectASession() {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No sessions listed")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "No detail for the selected session")
    }

    /// `item` of the menu bar's `menu`, with the menu left open; Escape closes it.
    @MainActor
    private func menuItem(_ menu: String, _ item: String) -> XCUIElement {
        let bar = app.menuBars.menuBarItems[menu]
        XCTAssertTrue(bar.waitForExistence(timeout: Self.timeout), "No \(menu) menu")
        bar.click()
        let entry = bar.menus.menuItems[item]
        XCTAssertTrue(entry.waitForExistence(timeout: Self.timeout), "No \(menu) ▸ \(item)")
        return entry
    }

    @MainActor
    func testTheSessionMenuActsOnTheSelectedSession() throws {
        selectASession()

        // A menu of its own, between View and Project.
        let titles = app.menuBars.menuBarItems.allElementsBoundByIndex.map(\.title)
        let session = try XCTUnwrap(titles.firstIndex(of: "Session"), "No Session menu: \(titles)")
        let view = try XCTUnwrap(titles.firstIndex(of: "View"))
        let project = try XCTUnwrap(titles.firstIndex(of: "Project"))
        XCTAssertTrue(view < session && session < project, "Session is not between View and Project: \(titles)")
        XCTAssertTrue(menuItem("Session", "New Project from Session").isEnabled)
        app.typeKey(.escape, modifierFlags: [])

        // With no project in front, the project's commands are dimmed; the attribute window, which
        // works without a project, is not.
        XCTAssertFalse(menuItem("Project", "Add Video…").isEnabled, "Add Video… is live with no project")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(menuItem("Project", "Map Attributes…").isEnabled)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertFalse(menuItem("Playback", "Play").isEnabled, "Play is live with no project")
        app.typeKey(.escape, modifierFlags: [])

        // Session ▸ Coach… opens Coaching on the session, as the detail's button does.
        menu("Session", "Coach…")
        let coaching = app.windows["Coaching"]
        XCTAssertTrue(coaching.waitForExistence(timeout: Self.timeout * 2), "Coach… did not open Coaching")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(coaching.waitForNonExistence(timeout: Self.timeout))

        // ⌃⌘C from the Logbook does the same: Project ▸ Coaching…, dimmed, does not take the key.
        menu("Window", "Logbook")
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout))
        app.typeKey("c", modifierFlags: [.command, .control])
        XCTAssertTrue(coaching.waitForExistence(timeout: Self.timeout * 2), "⌃⌘C did not reach Coach…")
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(coaching.waitForNonExistence(timeout: Self.timeout))

        // Session ▸ Remove from Logbook… asks first, and Cancel keeps the session.
        menu("Window", "Logbook")
        menu("Session", "Remove from Logbook…")
        XCTAssertTrue(removeConfirmation.waitForExistence(timeout: Self.timeout), "No confirmation")
        app.windows.buttons["Cancel"].click()
        XCTAssertTrue(removeConfirmation.waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(detail.exists, "Cancel removed the session")
    }

    @MainActor
    func testTheKeysSwitchViewsFindAndRemove() throws {
        selectASession()

        // ⌘2 shows Trends, which has no session detail; ⌘1 brings the sessions back, and the detail.
        app.typeKey("2", modifierFlags: .command)
        XCTAssertTrue(detail.waitForNonExistence(timeout: Self.timeout), "⌘2 did not leave the sessions")
        app.typeKey("3", modifierFlags: .command)
        XCTAssertFalse(detail.exists)
        app.typeKey("1", modifierFlags: .command)
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "⌘1 did not bring the sessions back")

        // ⌘F puts the keyboard in the search field.
        app.typeKey("f", modifierFlags: .command)
        let search = app.searchFields.firstMatch
        let focused = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                ((element as? XCUIElement)?.value(forKey: "hasKeyboardFocus") as? Bool) == true
            }, object: search)
        XCTAssertEqual(XCTWaiter().wait(for: [focused], timeout: Self.timeout), .completed, "⌘F did not find")
        app.typeText("zzzz")
        XCTAssertTrue(detail.waitForNonExistence(timeout: Self.timeout), "The search did not narrow")

        // ⌘⌫ in the search field deletes the text, as in any text field, and removes nothing.
        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "⌘⌫ did not clear the search")
        XCTAssertFalse(removeConfirmation.exists, "⌘⌫ in the search field asked to remove the session")

        // With the sessions in hand, ⌘⌫ asks to remove the selected one.
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        app.typeKey(.delete, modifierFlags: .command)
        XCTAssertTrue(removeConfirmation.waitForExistence(timeout: Self.timeout), "⌘⌫ did not ask to remove")
        app.windows.buttons["Cancel"].click()
        XCTAssertTrue(removeConfirmation.waitForNonExistence(timeout: Self.timeout))
    }
}
