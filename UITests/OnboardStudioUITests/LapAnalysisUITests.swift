import XCTest

// ci-shard: 4
/// J77: look at laps as data (#556). Analyse Laps… on a Logbook session lays its best two laps over
/// each other: delta-T, speed, the map and the friction circle, one cursor across them, and a
/// corner to zoom to.
final class LapAnalysisUITests: OnboardStudioUITestCase {
    @MainActor
    func testALogbookSessionsLapsAreLaidOverEachOther() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Session at a Circuit")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        app.buttons["trackday.done"].click()

        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let analyse = app.buttons["logbook.analyse"]
        XCTAssertTrue(analyse.waitForExistence(timeout: Self.timeout), "No Analyse Laps… on the session")
        reveal(analyse)
        analyse.click()

        let window = app.windows["Analysis"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "No Analysis window")
        let delta = window.descendants(matching: .any).matching(identifier: "analysis.delta").firstMatch
        XCTAssertTrue(delta.waitForExistence(timeout: Self.timeout * 2), "No delta-T trace")
        for panel in ["analysis.speed", "analysis.map", "analysis.frictionCircle"] {
            XCTAssertTrue(
                window.descendants(matching: .any).matching(identifier: panel).firstMatch.exists, "No \(panel)")
        }

        // A corner from the menu zooms every trace to it and puts the cursor on its apex.
        let wholeLap = window.buttons["analysis.wholeLap"]
        XCTAssertFalse(wholeLap.isEnabled, "Zoomed in before asked")
        let corners = window.menuButtons["analysis.corners"]
        corners.click()
        let first = corners.menuItems.firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: Self.timeout), "No corners to go to")
        let name = first.title
        first.click()
        XCTAssertTrue(wholeLap.isEnabled, "Not zoomed to the corner")
        let cursor = window.staticTexts["analysis.cursor"]
        XCTAssertTrue(text(of: cursor).contains(name), "The cursor is not at \(name): \(text(of: cursor))")
        let shot = XCTAttachment(screenshot: window.screenshot())
        shot.name = "Analysis zoomed to \(name)"
        shot.lifetime = .keepAlways
        add(shot)
        wholeLap.click()
        XCTAssertFalse(wholeLap.isEnabled, "Whole Lap did not show the whole lap")
    }

    /// The fixture session at a circuit, in an empty logbook, selected.
    @MainActor
    private func selectTheFixtureSession() {
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Session at a Circuit")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        app.buttons["trackday.done"].click()
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
    }

    /// The same laps from Coaching's Data view and from the Logbook's Analysis view (⌘4).
    @MainActor
    func testCoachingAndTheLogbookShowTheLapsAsDataToo() throws {
        launch(logbook: true)
        selectTheFixtureSession()

        app.typeKey("4", modifierFlags: .command)
        let inLogbook = app.windows["Logbook"].descendants(matching: .any).matching(identifier: "analysis.delta")
            .firstMatch
        XCTAssertTrue(inLogbook.waitForExistence(timeout: Self.timeout * 2), "No Analysis view in the Logbook")
        app.typeKey("1", modifierFlags: .command)

        let coach = app.buttons["logbook.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.timeout), "No Coach… on the session")
        reveal(coach)
        coach.click()
        let coaching = app.windows["Coaching"]
        XCTAssertTrue(coaching.waitForExistence(timeout: Self.timeout), "No Coaching window")
        let data = coaching.radioButtons["Data"].exists ? coaching.radioButtons["Data"] : coaching.buttons["Data"]
        XCTAssertTrue(data.waitForExistence(timeout: Self.timeout), "No Data view in Coaching")
        data.click()
        let inCoaching = coaching.descendants(matching: .any).matching(identifier: "analysis.delta").firstMatch
        XCTAssertTrue(inCoaching.waitForExistence(timeout: Self.timeout * 2), "No delta-T in Coaching's Data view")
        let reference = coaching.staticTexts["Reference"]
        XCTAssertTrue(reference.exists, "No reference lap marked")
    }

    /// A project's laps with its video: the picture at the cursor, and Play moving the cursor.
    @MainActor
    func testAProjectsLapsShowTheirPicture() throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "Data not listed")
        menu("Window", "Analysis")
        let window = app.windows["Analysis"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "No Analysis window")
        // The player is AppKit's view, which carries no identifier of SwiftUI's; its Play button does.
        let play = window.buttons["analysis.picture.play"]
        XCTAssertTrue(play.waitForExistence(timeout: Self.timeout * 2), "No picture of the lap")
        let cursor = window.staticTexts["analysis.cursor"]
        XCTAssertTrue(text(of: cursor).hasPrefix("Move over"), text(of: cursor))
        play.click()
        let moving = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT (value BEGINSWITH 'Move over') AND NOT (label BEGINSWITH 'Move over')"),
            object: cursor)
        XCTAssertEqual(
            XCTWaiter().wait(for: [moving], timeout: Self.timeout), .completed, "Play did not move the cursor")
        play.click()
    }
}
