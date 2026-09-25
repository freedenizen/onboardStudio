import XCTest

// ci-shard: 2
/// A video's own Crop, and the Frame every video shares (#274).
final class CropAndFrameUITests: OnboardStudioUITestCase {
    /// Crop holds the edges, rotation and flip together, and Reset Crop puts all of them back.
    @MainActor
    func testResetCropPutsBackEdgesAndRotation() throws {
        launch()
        addFixtureVideo()
        sidebarInput("test-3s").click()
        let top = app.textFields["crop.top.value"]
        XCTAssertTrue(top.waitForExistence(timeout: Self.timeout), "No Crop section in the video inspector")
        reveal(top)
        top.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("12\t")
        expect(top, toRead: "12")
        let rotation = app.popUpButtons["crop.rotation"]
        choosePopUpItem("90°", in: rotation)
        XCTAssertEqual(rotation.value as? String, "90°")

        let reset = app.buttons["crop.reset"]
        reveal(reset)
        reset.click()
        expect(top, toRead: "0")
        XCTAssertEqual(rotation.value as? String, "0°", "Reset Crop left the picture turned")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Reset Crop")
    }

    /// Frame is in the project inspector, and moving it needs a zoom first.
    @MainActor
    func testFrameIsInTheProjectInspector() throws {
        launch()
        addFixtureVideo()
        app.typeKey("a", modifierFlags: [.command, .shift])
        let zoom = app.textFields["frame.zoom.value"]
        let horizontal = app.sliders["frame.horizontal"]
        XCTAssertTrue(zoom.waitForExistence(timeout: Self.timeout), "No Frame section in the project inspector")
        reveal(horizontal)
        XCTAssertFalse(horizontal.isEnabled, "The frame can move before it is zoomed")
        zoom.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText("2\t")
        XCTAssertTrue(horizontal.isEnabled, "Zoomed in, the frame cannot move")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Zoom Frame")
    }
}
