import XCTest

// ci-shard: 1
/// Undo takes back what the user did, one action at a time, and says which (#243).
final class UndoUITests: OnboardStudioUITestCase {
    /// #243: dragging a slider is one undo step, not one per value it passed through. It already
    /// was — the slider tracks the whole drag inside its mouse-down event, and the undo manager
    /// groups by event — and this keeps it that way.
    @MainActor
    func testDraggingASliderIsOneUndoStep() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        let opacity = app.sliders["object.opacity"]
        XCTAssertTrue(opacity.waitForExistence(timeout: Self.timeout))
        reveal(opacity)
        let before = opacity.normalizedSliderPosition
        // A real drag, held down across the slider, so it reports many values on the way.
        // Retried once: a drag that starts while the inspector is still settling can miss the thumb.
        for _ in 0..<2 where opacity.normalizedSliderPosition > before - 0.3 {
            let thumb = opacity.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.5))
            thumb.press(
                forDuration: 0.3, thenDragTo: opacity.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)),
                withVelocity: .slow, thenHoldForDuration: 0.3)
        }
        XCTAssertLessThan(opacity.normalizedSliderPosition, before - 0.3, "The drag did not move the slider")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Change Opacity")
        // One ⌘Z puts it back, and the step before the drag is next.
        app.typeKey("z", modifierFlags: .command)
        let deadline = Date().addingTimeInterval(Self.timeout)
        while abs(opacity.normalizedSliderPosition - before) > 0.02, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertEqual(opacity.normalizedSliderPosition, before, accuracy: 0.02, "One ⌘Z did not undo the drag")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Add Speedometer")
    }
}
