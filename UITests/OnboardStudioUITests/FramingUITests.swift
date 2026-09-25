import XCTest

// ci-shard: 1
/// Framing the picture on the preview (#275): the frame drawn over the whole shot, moved and
/// zoomed there, Cancel putting it back and Done making the session one undo step.
final class FramingUITests: OnboardStudioUITestCase {
    var zoomBox: XCUIElement { app.textFields["frame.zoom.value"] }
    var frame: XCUIElement { app.descendants(matching: .any)["preview.frame"] }
    var done: XCUIElement { app.buttons["framing.done"] }

    @MainActor
    func openFraming() {
        launch()
        addFixtureVideo()
        app.typeKey("a", modifierFlags: [.command, .shift])
        XCTAssertTrue(zoomBox.waitForExistence(timeout: Self.timeout))
        menu("View", "Frame Picture")
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No bar over the preview")
        XCTAssertTrue(frame.waitForExistence(timeout: Self.timeout), "No frame on the preview")
    }

    /// The keys zoom it, and Cancel puts the framing back with nothing to undo.
    @MainActor
    func testCancelPutsTheFramingBack() throws {
        openFraming()
        app.typeKey("=", modifierFlags: [])
        app.typeKey("=", modifierFlags: [])
        expect(zoomBox, toContain: "1.21")
        app.buttons["framing.cancel"].click()
        XCTAssertTrue(done.waitForNonExistence(timeout: Self.timeout), "The bar stayed after Cancel")
        expect(zoomBox, toRead: "1")
        XCTAssertNotEqual(undoRedoTitles().undo, "Undo Reframe Videos")
    }

    /// A corner dragged in zooms the frame; Done keeps it as one step that ⌘Z takes back.
    @MainActor
    func testDraggingACornerAndDoneIsOneUndoStep() throws {
        openFraming()
        let corner = frame.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0))
        corner.press(forDuration: 0.2, thenDragTo: frame.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)))
        XCTAssertEqual(Double(zoomBox.value as? String ?? "") ?? 0, 2, accuracy: 0.15, "The corner did not zoom it")
        done.click()
        XCTAssertTrue(done.waitForNonExistence(timeout: Self.timeout))
        XCTAssertEqual(undoRedoTitles().undo, "Undo Reframe Videos")
        app.typeKey("z", modifierFlags: .command)
        expect(zoomBox, toRead: "1")
    }
}
