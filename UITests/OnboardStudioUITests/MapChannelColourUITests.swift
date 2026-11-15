import XCTest

// ci-shard: 4
/// J72: colour the map by a channel (#561). A Track Map paints the lap being driven by speed,
/// brake, throttle or any channel the data has, with a legend; delta colouring and channel
/// colouring take turns, and the colours are set once in Settings ▸ Maps.
final class MapChannelColourUITests: OnboardStudioUITestCase {
    @MainActor
    func testAMapPaintsTheLapByAChannelAndUndoTakesItBack() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Track Map")

        let channel = app.popUpButtons["trackMap.colorChannel"]
        XCTAssertTrue(channel.waitForExistence(timeout: Self.timeout), "No Colour by in the map's inspector")
        expect(channel, toRead: "Nothing")
        // A toggle in the inspector's grouped form is a switch, found by its identifier.
        let legend = app.switches["trackMap.legend"]
        XCTAssertFalse(legend.exists, "A legend before there is anything to explain")

        choosePopUpItem("Speed", in: channel)
        expect(channel, toRead: "Speed")
        XCTAssertTrue(legend.waitForExistence(timeout: Self.timeout), "No legend toggle once a channel paints the lap")
        XCTAssertEqual(legend.value as? Int, 1, "The legend shows by default")

        // Delta colouring paints the same line, so turning it on hands the lap over to it.
        let delta = app.switches["trackMap.colorByDelta"]
        reveal(delta)
        delta.click()
        expect(channel, toRead: "Nothing")
        menu("Edit", "Undo Change Delta Colouring")
        expect(channel, toRead: "Speed")

        // One undo step, named for what it takes back.
        menu("Edit", "Undo Change Channel Colouring")
        expect(channel, toRead: "Nothing")
        XCTAssertFalse(legend.exists, "The legend went with the channel")
    }

    @MainActor
    func testSettingsHoldTheColoursEveryMapUses() throws {
        launch()
        app.typeKey(",", modifierFlags: .command)
        let restore = app.buttons["settings.mapRamp.restore"]
        XCTAssertTrue(restore.waitForExistence(timeout: Self.timeout), "No Maps section in Settings")
        reveal(restore)
        // Untouched, the colours are the standard ramp, so there is nothing to restore.
        XCTAssertFalse(restore.isEnabled, "Restore enabled with the standard colours")
        for (index, name) in ["Lowest", "Low", "High", "Highest"].enumerated() {
            let well = app.descendants(matching: .any).matching(identifier: "settings.mapRamp.\(index)").firstMatch
            XCTAssertTrue(well.exists, "No well for the \(name.lowercased()) colour")
        }
    }
}
