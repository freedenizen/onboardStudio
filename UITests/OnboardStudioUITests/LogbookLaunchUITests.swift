import XCTest

// ci-shard: 2
/// J1: the Logbook is the window at launch, and a project — blank, or from a template — starts
/// from it (#395).
final class LogbookLaunchUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheLogbookOpensAtLaunchAndStartsABlankProject() throws {
        launch(logbook: true)
        let logbook = app.windows["Logbook"]
        XCTAssertTrue(logbook.waitForExistence(timeout: Self.timeout), "No Logbook window at launch")
        XCTAssertEqual(projectWindows.count, 0, "No project until the user asks for one")
        XCTAssertFalse(app.sheets.firstMatch.exists || app.dialogs.firstMatch.exists, "No Open panel at launch")
        XCTAssertTrue(app.buttons["logbook.empty.newTrackDay"].exists, "An empty logbook offers New Track Day…")
        let newProject = app.menuButtons["logbook.newProject"]
        XCTAssertTrue(newProject.waitForExistence(timeout: Self.timeout), "No New Project in the toolbar")
        newProject.click()
        let items = newProject.menus.menuItems
        for title in ["Blank Project", "Classic Dash", "Open Project…", "Templates…", "Open the Sample Project"] {
            XCTAssertTrue(items[title].waitForExistence(timeout: Self.timeout), "New Project offers \(title)")
        }
        items["Blank Project"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: Self.timeout), "Blank project")
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(logbook.exists, "The Logbook stays open behind the project")
    }

    @MainActor
    func testAProjectStartsFromATemplateInTheLogbook() throws {
        launch(logbook: true)
        let newProject = app.menuButtons["logbook.newProject"]
        XCTAssertTrue(newProject.waitForExistence(timeout: Self.timeout))
        newProject.click()
        let item = newProject.menus.menuItems["Glass Cockpit"]
        XCTAssertTrue(item.waitForExistence(timeout: Self.timeout))
        item.click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: Self.timeout))
        for label in ["Wheel", "Speed", "RPM", "Fade"] {
            XCTAssertTrue(sidebarObject(label).waitForExistence(timeout: Self.timeout), "Template object “\(label)”")
        }
        // The Templates window still holds the cards (Window ▸ Templates, or Templates… in that menu).
        menu("Window", "Templates")
        XCTAssertTrue(app.windows["Templates"].waitForExistence(timeout: Self.timeout), "No Templates window")
        XCTAssertTrue(app.buttons["launcher.template.Classic Dash"].waitForExistence(timeout: Self.timeout))
    }

    /// With a session selected, New Project in the toolbar makes the project from that session and
    /// says so, as the button in the session's detail does; a project with nothing in it is still
    /// one item away (#449: the toolbar's menu ignored the selection).
    @MainActor
    func testNewProjectInTheToolbarIsFromTheSelectedSession() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook window at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let row = table.descendants(matching: .any).matching(rowTypes).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No sessions listed")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(sessionNewProject.waitForExistence(timeout: Self.timeout), "No detail for the selected session")

        // The menu is about the session now: its heading names it, and the way round it is spelt out.
        let newProject = app.menuButtons["logbook.newProject"]
        newProject.click()
        let items = newProject.menus.menuItems
        XCTAssertTrue(items["New Project Without a Session"].waitForExistence(timeout: Self.timeout))
        let heading = items.matching(NSPredicate(format: "title BEGINSWITH 'From '")).firstMatch
        XCTAssertTrue(heading.exists, "The menu does not say which session the project is from")
        // The project is called what the heading calls the session, not "Untitled" (#481).
        let name = String(heading.title.dropFirst("From ".count))
        XCTAssertFalse(items["From a Template"].exists, "The templates are the session's while it is selected")
        items["Blank Project"].click()
        let project = app.windows[name]
        XCTAssertTrue(project.waitForExistence(timeout: Self.timeout), "No project called “\(name)”")
        let inputs = project.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'input.'"))
        XCTAssertTrue(inputs.firstMatch.waitForExistence(timeout: Self.timeout * 2), "The session's file is not in it")

        // And without the session: a project with nothing in it, and so Untitled.
        menu("Window", "Logbook")
        toolbarMenu("logbook.newProject", "New Project Without a Session")
        let empty = app.windows["Untitled"]
        XCTAssertTrue(empty.waitForExistence(timeout: Self.timeout), "No second project")
        XCTAssertTrue(empty.staticTexts["welcome.title"].waitForExistence(timeout: Self.timeout), "It is not empty")
    }
}
