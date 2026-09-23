import XCTest

/// J17: save a layout as a template, find it in the welcome window with a picture, manage it
/// there, and start a project from it (#44).
final class TemplateLibraryUITests: OnboardStudioUITestCase {
    @MainActor
    func testSaveManageAndStartFromYourOwnTemplate() throws {
        launch()
        toolbarMenu("toolbar.addObject", "Title Card")
        XCTAssertTrue(sidebarObject("Text").waitForExistence(timeout: Self.timeout))

        // Save it from a sheet that shows what goes in.
        menu("Project", "Save as Template…")
        let name = app.textFields["saveTemplate.name"]
        XCTAssertTrue(name.waitForExistence(timeout: Self.timeout), "No Save as Template sheet")
        name.click()
        app.typeKey("a", modifierFlags: .command)
        name.typeText("Club Day\n")
        expectStatus(containing: "Saved the template “Club Day”")

        // It waits in the welcome window beside the built-in ones.
        menu("Help", "Welcome to Onboard Studio")
        let card = app.buttons["launcher.template.Club Day"]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout), "Your template is not in the welcome window")

        // Rename and duplicate it from a right-click, as in the Finder.
        contextMenu(on: card, "Rename…")
        let field = app.textFields["launcher.renameTemplate"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "No rename field")
        field.click()
        app.typeKey("a", modifierFlags: .command)
        field.typeText("Club Weekend\n")
        let renamed = app.buttons["launcher.template.Club Weekend"]
        XCTAssertTrue(renamed.waitForExistence(timeout: Self.timeout), "Rename did not take")
        XCTAssertFalse(card.exists)
        contextMenu(on: renamed, "Duplicate")
        let copy = app.buttons["launcher.template.Club Weekend copy"]
        XCTAssertTrue(copy.waitForExistence(timeout: Self.timeout), "No duplicate")

        // Deleting asks first.
        contextMenu(on: copy, "Delete…")
        // Scoped to windows: the Touch Bar carries a copy of the dialog's buttons.
        let trash = app.windows.buttons["Move to Trash"].firstMatch
        XCTAssertTrue(trash.waitForExistence(timeout: Self.timeout), "Delete did not ask")
        trash.click()
        XCTAssertTrue(copy.waitForNonExistence(timeout: Self.timeout))

        // A new project from it has the saved layout.
        renamed.click()
        XCTAssertTrue(
            app.staticTexts.matching(identifier: "object.Text").element(boundBy: 1).waitForExistence(
                timeout: Self.timeout),
            "The new project does not have the template's objects")
    }

    /// Chooses `item` from the context menu of `element`. The menu bar has items of the same name
    /// (File ▸ Rename…, Duplicate), always in the tree but never on screen, so the one to click is
    /// the one that can be hit.
    @MainActor
    func contextMenu(on element: XCUIElement, _ item: String) {
        element.rightClick()
        let candidates = app.menuItems.matching(NSPredicate(format: "title == %@", item))
        let deadline = Date().addingTimeInterval(Self.timeout)
        while Date() < deadline {
            if let entry = candidates.allElementsBoundByIndex.first(where: \.isHittable) {
                entry.click()
                return
            }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTFail("No “\(item)” on the context menu")
    }
}
