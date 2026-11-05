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
        XCTAssertFalse(app.windows["Untitled"].exists, "No project until the user asks for one")
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
}
