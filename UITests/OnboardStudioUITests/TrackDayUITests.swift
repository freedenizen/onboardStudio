import XCTest

// ci-shard: 2
/// J37: a track day into the logbook — files and folders in, a line per file out (#346).
final class TrackDayUITests: OnboardStudioUITestCase {
    @MainActor
    func testAFolderOfSessionsIsEnteredAndReportedPerFile() throws {
        launch()
        // The Testing menu stands in for the open panel: the fixtures folder is the track day.
        // The command the journey names lives in File, with the other ways of bringing files in;
        // the hook below stands in for its open panel.
        let file = app.menuBars.menuBarItems["File"]
        XCTAssertTrue(file.waitForExistence(timeout: Self.timeout), "No File menu")
        file.click()
        XCTAssertTrue(
            file.menus.menuItems["Add Files to Logbook…"].waitForExistence(timeout: Self.timeout),
            "File ▸ Add Files to Logbook… is missing")
        app.typeKey(.escape, modifierFlags: [])
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        let summary = app.staticTexts["trackday.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout * 3), "The import did not finish")
        let text = summary.value as? String ?? summary.label
        XCTAssertTrue(text.contains("sessions added"), text)
        XCTAssertFalse(text.hasPrefix("0 "), text)
        done.click()
        XCTAssertTrue(done.waitForNonExistence(timeout: Self.timeout))
        expectStatus(containing: "to the logbook")
    }

    /// #455: a file from a place the catalogue does not know used to become a circuit of its own
    /// in the sidebar, named after the file. Such sessions are gathered as "No circuit", and
    /// naming the circuit on their day names it on them.
    @MainActor
    func testSessionsWithNoCircuitAreGatheredAndTakeTheNameTheirDayIsGiven() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout))
        // A day begun without saying where: the fixtures onto it, whatever their dates.
        app.buttons["logbook.newTrackDay"].click()
        let create = app.buttons["trackday.new.create"]
        XCTAssertTrue(create.waitForExistence(timeout: Self.timeout), "No New Track Day sheet")
        create.click()
        let title = app.staticTexts["trackday.header.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "No day header")
        expect(title, toRead: "Track day")
        testing("Add Fixture Sessions to Selected Day")
        finishAddingToDay(.thisDay)

        // One entry for the sessions that name no circuit, and none called after a file.
        let sidebar = app.descendants(matching: .any).matching(identifier: "logbook.sidebar").firstMatch
        XCTAssertTrue(sidebar.staticTexts["No circuit"].waitForExistence(timeout: Self.timeout), "No “No circuit”")
        for file in ["generic", "harrys", "coaching-laps", "racerender-basic", "activity"] {
            XCTAssertFalse(sidebar.staticTexts[file].exists, "A circuit is named after the file \(file)")
        }
        XCTAssertTrue(sidebar.staticTexts["Sonoma Raceway"].exists, "A recognised circuit is still listed")

        // The day is named in its header; the catalogue does not know the place, so as typed.
        let field = app.textFields["trackday.header.circuit"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "The day's header has no Circuit field")
        field.click()
        field.typeText("Stadium")
        let asTyped = app.descendants(matching: .any).matching(identifier: "trackday.header.useTyped").firstMatch
        XCTAssertTrue(asTyped.waitForExistence(timeout: Self.timeout), "No way to keep the name as typed")
        asTyped.click()

        // The day, its sessions and the sidebar follow; the sessions that said where they were stay.
        expect(title, toRead: "Stadium")
        XCTAssertTrue(sidebar.staticTexts["Stadium"].waitForExistence(timeout: Self.timeout), "No Stadium circuit")
        XCTAssertTrue(sidebar.staticTexts["No circuit"].waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(sidebar.staticTexts["Sonoma Raceway"].exists, "A recognised session changed circuit")
        let day = "\(Date().formatted(date: .abbreviated, time: .omitted)) · Stadium"
        XCTAssertTrue(
            app.staticTexts["logbook.day.\(day)"].waitForExistence(timeout: Self.timeout),
            "The day lost its place in the sidebar when it was named")
        XCTAssertTrue(app.staticTexts["trackday.header.circuit.chosen"].exists, "The header does not show the choice")
    }
}
