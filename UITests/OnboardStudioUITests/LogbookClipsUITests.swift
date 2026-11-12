import XCTest

// ci-shard: 1
/// J48: the day's clips are kept with its sessions, assigned by hand when the clocks cannot say,
/// and go into a new project with the data (#394).
final class LogbookClipsUITests: OnboardStudioUITestCase {
    @MainActor
    func testAClipIsAssignedAndANewProjectHasVideoAndData() throws {
        launch()
        menu("Window", "Logbook")
        let newDay = app.buttons["logbook.newTrackDay"]
        XCTAssertTrue(newDay.waitForExistence(timeout: Self.timeout))
        newDay.click()
        let search = app.textFields["trackday.new.circuit"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "No New Track Day sheet")
        search.click()
        search.typeText("Thunderhill")
        app.descendants(matching: .any).matching(identifier: "trackday.new.useTyped").firstMatch.click()
        app.buttons["trackday.new.create"].click()
        XCTAssertTrue(app.staticTexts["trackday.header.title"].waitForExistence(timeout: Self.timeout))

        // The fixtures onto the day, whatever their dates: the clip has no clock the sessions agree
        // with, so it waits.
        testing("Add Fixture Sessions to Selected Day")
        let summary = finishAddingToDay(.thisDay)
        XCTAssertTrue(summary.contains("clip"), summary)
        let clip = app.popUpButtons["trackday.clip.test-3s.mp4"]
        XCTAssertTrue(clip.waitForExistence(timeout: Self.timeout), "The clip is not listed on the day")
        XCTAssertEqual(clip.value as? String, "Not assigned")

        // Assign it to the RaceChrono session by hand, then the session knows its video.
        clip.click()
        let sessions = clip.menus.menuItems
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 1"), object: sessions)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "No sessions to choose")
        sessions.element(boundBy: 1).click()
        let assigned = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH 'Session'"), object: clip)
        XCTAssertEqual(
            XCTWaiter().wait(for: [assigned], timeout: Self.timeout), .completed, clip.value as? String ?? "")

        // Every session listed is a row; the one with the clip shows it under Video.
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let video = app.descendants(matching: .any).matching(identifier: "logbook.clip.test-3s.mp4").firstMatch
        var found = false
        for index in 0..<min(rows.count, 8) where !found {
            rows.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
            XCTAssertTrue(sessionNewProject.waitForExistence(timeout: Self.timeout))
            found = video.waitForExistence(timeout: 1)
        }
        XCTAssertTrue(found, "No session lists the clip under Video")

        // New Project: the clip and the data file, laid out.
        pressSplitButton(sessionNewProject)
        XCTAssertTrue(projectWindows.firstMatch.waitForExistence(timeout: Self.timeout), "No new project")
        XCTAssertTrue(
            sidebarInput("test-3s").waitForExistence(timeout: Self.timeout * 2), "The clip is not a video input")
        let data = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'input.'"))
        let both = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: data)
        XCTAssertEqual(XCTWaiter().wait(for: [both], timeout: Self.timeout), .completed, "No data input beside it")
        XCTAssertTrue(sidebarObject("Speed").waitForExistence(timeout: Self.timeout), "Classic Dash was not applied")
    }
}
