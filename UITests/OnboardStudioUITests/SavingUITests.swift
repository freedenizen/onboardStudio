import XCTest

// ci-shard: 3
/// J32: try an edit and walk away from it; the project file changes only when you save (#300).
final class SavingUITests: OnboardStudioUITestCase {
    /// Closing asks, and Don't Save leaves the file as it was, however long the edit sat there.
    @MainActor
    func testEditsAreNotWrittenUntilSaved() throws {
        let window = openFixtureAndHideSpeed()
        sleep(8)  // longer than the autosave delay: autosaving in place would have written it by now
        app.typeKey("w", modifierFlags: .command)
        let dontSave = window.sheets.buttons["Don’t Save"]  // AppKit's title has a typographic apostrophe
        XCTAssertTrue(dontSave.waitForExistence(timeout: Self.timeout), "Closing an edited project asks to save it")
        dontSave.click()
        XCTAssertTrue(window.waitForNonExistence(timeout: Self.timeout))
        testing("Open Fixture Project")
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["Hide Speed"].waitForExistence(timeout: Self.timeout), "The file was left as saved")
    }

    /// The edits are kept aside all the same: after a crash the project comes back with them,
    /// still unsaved.
    @MainActor
    func testUnsavedEditsSurviveACrash() throws {
        openFixtureAndHideSpeed(restoresState: true)
        sleep(8)  // let the autosave write them aside
        let kill = Process()
        kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        kill.arguments = ["-9", "-x", "OnboardStudio"]
        try kill.run()
        kill.waitUntilExit()
        launch(restoresState: true)
        let window = app.windows["slice.onboardproj"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "The project reopens after the crash")
        XCTAssertTrue(app.buttons["Show Speed"].waitForExistence(timeout: Self.timeout), "The edit came back")
    }

    @MainActor
    @discardableResult
    private func openFixtureAndHideSpeed(restoresState: Bool = false) -> XCUIElement {
        launch(restoresState: restoresState)
        testing("Open Fixture Project")
        let window = app.windows["slice.onboardproj"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "Fixture project window")
        XCTAssertTrue(sidebarObject("Speed").waitForExistence(timeout: Self.timeout))
        app.buttons["Hide Speed"].click()
        XCTAssertTrue(app.buttons["Show Speed"].waitForExistence(timeout: Self.timeout))
        return window
    }
}
