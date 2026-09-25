import XCTest

// ci-shard: 3
/// Getting back to nothing selected, and the inspector out of the way (#280).
final class DeselectUITests: OnboardStudioUITestCase {
    /// The first control of the project inspector: the form builds rows lazily, so one further
    /// down may not exist until scrolled to.
    var projectInspector: XCUIElement { app.popUpButtons["project.outputSize"] }
    var objectInspector: XCUIElement { app.sliders["object.opacity"] }

    /// Edit ▸ Deselect All (⇧⌘A) returns the inspector to the project, and is off when there is
    /// nothing to deselect.
    @MainActor
    func testDeselectAllClearsTheSelection() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        XCTAssertTrue(objectInspector.waitForExistence(timeout: Self.timeout), "Adding did not select the object")
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(projectInspector.waitForExistence(timeout: Self.timeout), "⇧⌘A did not deselect")
        XCTAssertFalse(objectInspector.exists)
        app.menuBarItems["Edit"].click()
        XCTAssertFalse(
            app.menuBarItems["Edit"].menus.menuItems["Deselect All"].isEnabled,
            "Deselect All is on with nothing selected")
        app.typeKey(.escape, modifierFlags: [])
    }

    /// A click on empty space in the sidebar selects nothing, as in the Finder's lists.
    @MainActor
    func testClickingEmptySidebarDeselects() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        XCTAssertTrue(objectInspector.waitForExistence(timeout: Self.timeout))
        let sidebar = app.outlines["Sidebar"]
        // Near the bottom of the sidebar, well below the last row.
        sidebar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).click()
        XCTAssertTrue(projectInspector.waitForExistence(timeout: Self.timeout), "Empty space did not deselect")
    }

    /// View ▸ Hide Inspector (⌥⌘I) and the toolbar button hide and show it, and the menu item says
    /// which it will do.
    @MainActor
    func testTheInspectorHidesAndShows() throws {
        launch()
        XCTAssertTrue(projectInspector.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.menuBarItems["View"].menus.menuItems["Hide Inspector"].exists)

        app.typeKey("i", modifierFlags: [.command, .option])
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: projectInspector)
        waitForExpectations(timeout: Self.timeout)
        XCTAssertTrue(app.menuBarItems["View"].menus.menuItems["Show Inspector"].exists)

        app.buttons["toolbar.inspector"].firstMatch.click()
        XCTAssertTrue(projectInspector.waitForExistence(timeout: Self.timeout), "The toolbar button did not show it")
    }
}
