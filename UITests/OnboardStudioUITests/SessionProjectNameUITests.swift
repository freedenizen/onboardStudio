import XCTest

// ci-shard: 5
/// J38: a project made from a session is called after the session, as the Logbook lists it, until
/// it is saved (#481) — not "Untitled" — a second one from the same session is numbered, and a
/// saved one is called by its file.
final class SessionProjectNameUITests: OnboardStudioUITestCase {
    @MainActor
    func testASessionsProjectIsCalledAfterItUntilItIsSaved() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let row = table.descendants(matching: .any).matching(
            NSPredicate(
                format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
                XCUIElement.ElementType.outlineRow.rawValue)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No sessions listed")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(sessionNewProject.waitForExistence(timeout: Self.timeout), "No detail for the session")

        // The name the Logbook gives the session, from the heading of the toolbar's New Project.
        let newProject = app.menuButtons["logbook.newProject"]
        newProject.click()
        let heading = newProject.menus.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'From '")).firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: Self.timeout), "The menu does not name the session")
        let name = String(heading.title.dropFirst("From ".count))
        app.typeKey(.escape, modifierFlags: [])

        pressSplitButton(sessionNewProject)
        XCTAssertTrue(app.windows[name].waitForExistence(timeout: Self.timeout), "No project called “\(name)”")
        XCTAssertFalse(app.windows["Untitled"].exists, "The project is still Untitled")

        // Another from the same session is numbered, as a second Untitled is.
        menu("Window", "Logbook")
        pressSplitButton(sessionNewProject)
        let second = app.windows["\(name) 2"]
        XCTAssertTrue(second.waitForExistence(timeout: Self.timeout), "No project called “\(name) 2”")

        // Saved, it is called by its file.
        second.click()
        testing("Save Project as Scratch File")
        let saved = app.windows.matching(NSPredicate(format: "title BEGINSWITH 'Saved Track Day'")).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: Self.timeout), "Saved, the project is not called by its file")
        XCTAssertTrue(second.waitForNonExistence(timeout: Self.timeout), "Saved, it kept the session's name")
        XCTAssertTrue(app.windows[name].exists, "The first project lost its name")
    }
}
