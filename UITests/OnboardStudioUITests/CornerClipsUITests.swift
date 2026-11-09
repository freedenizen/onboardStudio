import XCTest

// ci-shard: 1
/// J52: export every corner slowed through its braking zone, with a sight picture held (#360).
final class CornerClipsUITests: OnboardStudioUITestCase {
    @MainActor
    func testCornerClipsSlowTheBrakingZoneAndHoldASightPicture() throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout))
        app.buttons["toolbar.export"].click()
        choose("Every corner, one file each", inPopUpShowing: "Whole project")
        // A fresh choice slows the braking zone to half speed and holds a second.
        // A grouped form draws a toggle as a switch, so it is found by identifier, whatever its type.
        let slow = app.descendants(matching: .any).matching(identifier: "export.slowBraking").firstMatch
        let hold = app.descendants(matching: .any).matching(identifier: "export.holdReference").firstMatch
        XCTAssertTrue(slow.waitForExistence(timeout: Self.timeout), "No braking-zone switch")
        XCTAssertEqual("\(slow.value ?? "")", "1", "The braking zone should be slowed by default")
        XCTAssertEqual("\(hold.value ?? "")", "1", "The sight picture should be held by default")
        XCTAssertTrue(app.popUpButtons["export.brakingRate"].exists)
        XCTAssertTrue(app.popUpButtons["export.referenceHold"].exists)
        // The sheet says what the clips will do before it writes them.
        let files = app.staticTexts["export.cornerFiles"]
        expect(files, toContain: "Turn 1")
        expect(files, toContain: "the braking zone at 50% and a 1-second hold where the reference braked")
        // A switch turned off takes its control with it, and the sentence follows.
        reveal(hold)
        hold.click()
        XCTAssertFalse(app.popUpButtons["export.referenceHold"].waitForExistence(timeout: 2))
        expect(files, toContain: "the braking zone at 50%.")
        choose("25%", inPopUpShowing: "50%")
        expect(files, toContain: "the braking zone at 25%.")
    }
}
