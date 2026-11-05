import XCTest

// ci-shard: 1
/// J51: a session's laps raced round the circuit in 3D from the logbook — the quickest laps
/// chosen to begin with, cameras, the scrubber and a jump to a turn (#415).
final class ReplayUITests: OnboardStudioUITestCase {
    @MainActor
    func testLapsAreReplayedFromTheLogbook() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout))
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()

        // The coaching fixture: four laps of a stadium circuit.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout))
        search.click()
        search.typeText("coaching-laps")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let one = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [one], timeout: Self.timeout), .completed)
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let replay = app.buttons["logbook.replay"]
        XCTAssertTrue(replay.waitForExistence(timeout: Self.timeout), "No Replay… in the detail")
        replay.click()

        // The window: the three quickest laps chosen and standing, the scene, the HUD.
        let window = app.windows["Replay"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "No Replay window")
        let standings = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'replay.standing.'"))
        let three = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 3"), object: standings)
        XCTAssertEqual(XCTWaiter().wait(for: [three], timeout: Self.timeout * 3), .completed, "Three laps expected")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "replay.minimap").firstMatch.exists, "No map")
        let time = app.staticTexts["replay.time"]
        XCTAssertTrue(time.waitForExistence(timeout: Self.timeout))
        expect(time, toRead: "0:00.0")

        // Scrub: the clock and the HUD follow.
        let scrubber = app.sliders["replay.scrubber"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: Self.timeout), "No scrubber")
        scrubber.adjust(toNormalizedSliderPosition: 0.5)
        let moved = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != '0:00.0'"), object: time)
        XCTAssertEqual(XCTWaiter().wait(for: [moved], timeout: Self.timeout), .completed, time.value as? String ?? "")
        let hudTime = app.descendants(matching: .any).matching(identifier: "replay.hud.time").firstMatch
        XCTAssertTrue(hudTime.exists, "No lap time in the HUD")

        // Cameras: a segmented control in the toolbar; Above is the third.
        let above = app.radioButtons["Above"].firstMatch
        XCTAssertTrue(above.waitForExistence(timeout: Self.timeout), "No camera control")
        above.click()
        XCTAssertTrue(above.isSelected || (above.value as? Int) == 1)

        // A jump to a turn: the stadium has two.
        let turns = app.menuButtons["replay.goToTurn"]
        XCTAssertTrue(turns.waitForExistence(timeout: Self.timeout), "No Go to Turn")
        turns.click()
        let turn1 = turns.menus.menuItems["Turn 1"]
        XCTAssertTrue(turn1.waitForExistence(timeout: Self.timeout), "No Turn 1")
        turn1.click()
        XCTAssertTrue(time.waitForExistence(timeout: Self.timeout))

        // Untick a lap: the standings shrink.
        let laps = app.checkBoxes.matching(NSPredicate(format: "identifier BEGINSWITH 'replay.lap.'"))
        XCTAssertGreaterThan(laps.count, 3, "The session's complete laps are listed")
        let chosen = laps.allElementsBoundByIndex.first { ($0.value as? Int) == 1 }
        XCTAssertNotNil(chosen, "No chosen lap in the list")
        chosen?.click()
        let two = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 2"), object: standings)
        XCTAssertEqual(XCTWaiter().wait(for: [two], timeout: Self.timeout * 2), .completed, "The lap was not dropped")
    }
}
