import XCTest

// ci-shard: 1
/// Cropping a video on the preview (#276): the crop drawn over the whole picture, its edges
/// dragged, the picture turned from the bar, and the session one undo step.
final class CroppingUITests: OnboardStudioUITestCase {
    var crop: XCUIElement { app.descendants(matching: .any)["preview.crop"] }
    var top: XCUIElement { app.textFields["crop.top.value"] }
    var left: XCUIElement { app.textFields["crop.left.value"] }
    var rotation: XCUIElement { app.popUpButtons["crop.rotation"] }

    @MainActor
    func openCropping() {
        launch()
        addFixtureVideo()
        sidebarInput("test-3s").click()
        let button = app.buttons["crop.onPreview"]
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "No Crop on Preview in the video inspector")
        reveal(button)
        button.click()
        XCTAssertTrue(crop.waitForExistence(timeout: Self.timeout), "No crop on the preview")
    }

    /// An edge dragged in cuts the picture; Rotate Right turns it; Done is one step, Crop Video,
    /// that ⌘Z takes back whole.
    @MainActor
    func testDraggingAnEdgeAndTurningIsOneUndoStep() throws {
        openCropping()
        let edge = crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        edge.press(forDuration: 0.2, thenDragTo: crop.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2)))
        XCTAssertEqual(Double(top.value as? String ?? "") ?? 0, 20, accuracy: 3, "The top edge did not come in")
        app.buttons["Rotate Right"].firstMatch.click()
        XCTAssertEqual(rotation.value as? String, "90°")
        app.buttons["framing.done"].click()
        XCTAssertTrue(app.buttons["framing.done"].waitForNonExistence(timeout: Self.timeout))
        XCTAssertEqual(undoRedoTitles().undo, "Undo Crop Video")
        app.typeKey("z", modifierFlags: .command)
        expect(top, toRead: "0")
        XCTAssertEqual(rotation.value as? String, "0°")
    }

    /// A fixed shape is applied at once, as large as it fits; Cancel puts the picture back.
    @MainActor
    func testASquareIsFittedAndCancelPutsItBack() throws {
        openCropping()
        choosePopUpItem("Square", in: app.popUpButtons["crop.aspect"])
        // A square of a 16:9 picture keeps 9/16 of its width: 22 % comes off either side.
        expect(left, toRead: "22")
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.buttons["framing.done"].waitForNonExistence(timeout: Self.timeout))
        expect(left, toRead: "0")
        XCTAssertNotEqual(undoRedoTitles().undo, "Undo Crop Video")
    }
}
