import XCTest

// ci-shard: 2
/// J50: from a session in the logbook straight to a comparison and to a debrief (#397).
final class LogbookActionsUITests: OnboardStudioUITestCase {
    @MainActor
    func testASessionIsComparedAndDebriefedFromTheLogbook() throws {
        prepareDayWithClip()

        // The coaching-laps session: Compare With offers the other visit, and opens the window on it.
        let field = app.searchFields.firstMatch
        field.click()
        field.typeText("coaching-laps")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let two = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [two], timeout: Self.timeout), .completed, "Two visits expected")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let compare = app.menuButtons["logbook.compareWith"]
        XCTAssertTrue(compare.waitForExistence(timeout: Self.timeout), "No Compare With")
        compare.click()
        let choice = compare.menus.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Personal Best Here'"))
            .firstMatch
        XCTAssertTrue(choice.waitForExistence(timeout: Self.timeout), "No personal best to compare with")
        choice.click()
        let headline = app.staticTexts["coaching.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: Self.timeout * 2), "No coaching reading")
        // The day's circuit was typed, and the fixture names none: both visits are at the day's
        // (#455), where each used to be at a circuit named after its file.
        expect(headline, toContain: "Thunderhill")
        app.typeKey("w", modifierFlags: .command)

        // The session that took the clip (whichever the pop-up listed first): a debrief project
        // with the sheet up.
        field.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeKey(.delete, modifierFlags: [])
        let all = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 3"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [all], timeout: Self.timeout), .completed)
        let debrief = app.buttons["logbook.debrief"]
        var found = false
        for index in 0..<min(rows.count, 10) where !found {
            rows.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
            XCTAssertTrue(debrief.waitForExistence(timeout: Self.timeout))
            found = debrief.isEnabled
        }
        XCTAssertTrue(found, "No session with a clip offers a debrief")
        debrief.click()
        XCTAssertTrue(projectWindows.firstMatch.waitForExistence(timeout: Self.timeout), "No project")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "debrief.corners").firstMatch.waitForExistence(
                timeout: Self.timeout * 3), "No debrief sheet")
    }

    /// A day with the fixtures and a second visit at the coaching fixture's "circuit", the clip
    /// assigned to a session by hand.
    @MainActor
    private func prepareDayWithClip() {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout))
        // A day with the fixtures, then a second visit at the coaching fixture's "circuit".
        app.buttons["logbook.newTrackDay"].click()
        let search = app.textFields["trackday.new.circuit"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout))
        search.click()
        search.typeText("Thunderhill")
        app.descendants(matching: .any).matching(identifier: "trackday.new.useTyped").firstMatch.click()
        app.buttons["trackday.new.create"].click()
        XCTAssertTrue(app.staticTexts["trackday.header.title"].waitForExistence(timeout: Self.timeout))
        testing("Add Fixture Sessions to Selected Day")
        finishAddingToDay(.thisDay)
        testing("Add Fixture Second Visit")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()

        // The clip onto the RaceChrono session, so a debrief has a picture.
        let clip = app.popUpButtons["trackday.clip.test-3s.mp4"]
        XCTAssertTrue(clip.waitForExistence(timeout: Self.timeout), "The clip is not listed on the day")
        clip.click()
        let sessions = clip.menus.menuItems
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count > 1"), object: sessions)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed)
        sessions.element(boundBy: 1).click()
    }

}
