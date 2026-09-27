import XCTest

// ci-shard: 2
/// The screenshots in the README and the user guide (#304), taken from the real app.
///
/// Not a journey and not run on CI: it needs a real project, which is not in the repository. Run it
/// locally with the project and the moment to show:
///
///     TEST_RUNNER_ONBOARD_SCREENSHOT_PROJECT=/path/to/Project.onboardproj \
///     TEST_RUNNER_ONBOARD_SCREENSHOT_TIME=687 \
///     Scripts/screenshots.sh
///
/// Every picture is kept as an attachment of the result bundle; `Scripts/screenshots.sh` copies
/// them into `docs/images/`. The project is never saved: the run ends by quitting without saving.
final class DocumentationScreenshots: OnboardStudioUITestCase {
    @MainActor
    func testTakeScreenshots() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let project = environment["ONBOARD_SCREENSHOT_PROJECT"] else {
            throw XCTSkip("Set TEST_RUNNER_ONBOARD_SCREENSHOT_PROJECT to take the documentation screenshots")
        }
        let time = environment["ONBOARD_SCREENSHOT_TIME"] ?? "0"
        launch(
            extraArguments: ["-showGettingStarted", "NO"],
            environment: ["ONBOARD_TEST_SCREENSHOT_PROJECT": project, "ONBOARD_TEST_SCREENSHOT_TIME": time])

        testing("Open Screenshot Project")
        let name = URL(fileURLWithPath: project).lastPathComponent
        let window = app.windows[name]
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "No window for \(name)")
        testing("Size Window for Screenshots")
        menu("Project", "Apply Template", "Cockpit with Graph")
        app.typeKey("a", modifierFlags: [.command, .shift])
        choose("mph", inPopUpShowing: "Automatic")  // the project's speed unit, in the inspector
        testing("Seek to Screenshot Time")
        app.typeKey("a", modifierFlags: [.command, .shift])  // Deselect All: no handles on the picture
        settle()
        shoot(window, "editor")

        sidebarObject("RPM").click()
        settle()
        shoot(window, "inspector-gauge")
        app.typeKey("a", modifierFlags: [.command, .shift])

        menu("Project", "Export Video…")
        XCTAssertTrue(window.sheets.firstMatch.waitForExistence(timeout: Self.timeout), "No export sheet")
        settle()
        shoot(window, "export")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(window.sheets.firstMatch.waitForNonExistence(timeout: Self.timeout))

        menu("View", "Frame Picture")
        settle()
        shoot(window, "frame-picture")
        app.typeKey(.escape, modifierFlags: [])

        menu("Project", "Map Attributes…")
        let attributes = app.windows["Attributes"]
        XCTAssertTrue(attributes.waitForExistence(timeout: Self.timeout), "No Attributes window")
        settle()
        shoot(attributes, "attributes")
        app.typeKey("w", modifierFlags: .command)

        menu("Project", "Compare Laps…")
        let compare = app.buttons["compare.ok"]
        XCTAssertTrue(compare.waitForExistence(timeout: Self.timeout), "No Compare Laps sheet")
        compare.click()
        testing("Seek to Screenshot Time")
        app.typeKey("a", modifierFlags: [.command, .shift])
        settle()
        shoot(window, "compare-laps")

        menu("Help", "Welcome to Onboard Studio")
        let welcome = app.windows["Welcome to Onboard Studio"]
        XCTAssertTrue(welcome.waitForExistence(timeout: Self.timeout), "No welcome window")
        settle()
        shoot(welcome, "welcome")
    }

    /// Long enough for the preview to draw the frame at the playhead.
    private func settle() { sleep(3) }

    private func shoot(_ element: XCUIElement, _ name: String) {
        let attachment = XCTAttachment(screenshot: element.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
