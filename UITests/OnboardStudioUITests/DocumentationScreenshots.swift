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

        shootLogbookAndTemplates()
    }

    /// The Logbook with the project's files as a track day — the session and its clip, matched by
    /// the camera's GPS clock (#394, #408) — and the Templates window.
    @MainActor
    private func shootLogbookAndTemplates() {
        // The Logbook with the project's files as a track day: the session and its clip, matched
        // by the camera's GPS clock (#394, #408).
        menu("Window", "Logbook")
        let logbook = app.windows["Logbook"]
        XCTAssertTrue(logbook.waitForExistence(timeout: Self.timeout), "No Logbook window")
        testing("Enter Screenshot Project in Logbook")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 6))
        done.click()
        let day = app.staticTexts.matching(NSPredicate(format: "identifier BEGINSWITH 'logbook.day.'")).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: Self.timeout), "No track day in the sidebar")
        day.click()
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let row = table.descendants(matching: .any).matching(rowTypes).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No session under the day")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        XCTAssertTrue(sessionNewProject.waitForExistence(timeout: Self.timeout))
        settle()
        shoot(logbook, "logbook")
        // The same session raced in 3D (#415): the standings up and the cars a few seconds in.
        app.buttons["logbook.replay"].click()
        let replay = app.windows["Replay"]
        XCTAssertTrue(replay.waitForExistence(timeout: Self.timeout), "No Replay window")
        let standings = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'replay.standing.'"))
        let raced = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 0"), object: standings)
        XCTAssertEqual(XCTWaiter().wait(for: [raced], timeout: Self.timeout * 3), .completed, "No laps in the replay")
        app.sliders["replay.scrubber"].adjust(toNormalizedSliderPosition: 0.3)
        settle()
        shoot(replay, "replay")
        app.typeKey("w", modifierFlags: .command)
        app.typeKey("w", modifierFlags: .command)
        menu("Window", "Templates")
        let templates = app.windows["Templates"]
        XCTAssertTrue(templates.waitForExistence(timeout: Self.timeout), "No Templates window")
        settle()
        shoot(templates, "templates")
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
