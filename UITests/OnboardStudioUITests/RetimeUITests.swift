import XCTest

// ci-shard: 2
/// J53: slow down part of the video and hold a frame, picture and overlays together (#443).
final class RetimeUITests: OnboardStudioUITestCase {
    var lane: XCUIElementQuery { app.descendants(matching: .any) }

    @MainActor
    func testSlowARangeAndHoldAFrame() throws {
        launch()
        addFixtureVideo()
        // In at 0.5 s, Out at 1.5 s: Change Speed applies to the range between them.
        menu("Playback", "Go to Start")
        expect(transportTime, toRead: "0:00.00")
        for _ in 0..<15 { app.typeKey(".", modifierFlags: []) }
        app.typeKey("i", modifierFlags: [])
        expectStatus(containing: "In at 0:00.50")
        for _ in 0..<30 { app.typeKey(".", modifierFlags: []) }
        app.typeKey("o", modifierFlags: [])
        expectStatus(containing: "Out at 0:01.50")
        menu("Playback", "Change Speed of In to Out", "50%")
        expectStatus(containing: "plays at 50%")
        let slowed = lane["retime.50%"]
        XCTAssertTrue(slowed.waitForExistence(timeout: Self.timeout), "No band for the slowed range")
        XCTAssertEqual(slowed.label, "Plays at 50% from 0:00.50 to 0:01.50")
        XCTAssertTrue(editMenuItem("Undo Slow Down").exists, "Undo does not name the change")
        app.typeKey(.escape, modifierFlags: [])

        // ⇧H holds the frame at the playhead for a second.
        app.typeKey("h", modifierFlags: [.shift])
        expectStatus(containing: "Hold 1 s at 0:01.50")
        let hold = lane["retime.Hold 1 s"]
        XCTAssertTrue(hold.waitForExistence(timeout: Self.timeout), "No mark for the hold")
        // Its context menu changes or removes it; Undo brings it back.
        hold.rightClick()
        let remove = app.menuItems["Remove Hold"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: Self.timeout), "No Remove Hold in its menu")
        remove.click()
        XCTAssertTrue(hold.waitForNonExistence(timeout: Self.timeout), "The hold was not removed")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(hold.waitForExistence(timeout: Self.timeout), "Undo did not bring the hold back")

        // Normal Speed over the range takes the band away; the lane goes with the last retime.
        menu("Playback", "Change Speed of In to Out", "Normal Speed")
        XCTAssertTrue(slowed.waitForNonExistence(timeout: Self.timeout))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(slowed.waitForExistence(timeout: Self.timeout), "Undo did not bring the speed back")
    }

    /// The Edit menu's item named `title`, with the menu left open.
    func editMenuItem(_ title: String) -> XCUIElement {
        app.menuBarItems["Edit"].click()
        return app.menuBarItems["Edit"].menus.menuItems[title]
    }
}
