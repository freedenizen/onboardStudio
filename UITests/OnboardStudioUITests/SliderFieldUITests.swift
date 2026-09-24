import XCTest

// ci-shard: 3
/// Every slider has a box beside it for the exact value, and the graph's Now at returns to the
/// middle in one click (#266).
final class SliderFieldUITests: OnboardStudioUITestCase {
    /// Typing a value moves the slider, is one undo step with the slider's own name, and a value
    /// past the end of the slider stops at its end.
    @MainActor
    func testTypingAValueSetsTheSliderAndUndoesInOneStep() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        let slider = app.sliders["object.opacity"]
        let box = app.textFields["object.opacity.value"]
        XCTAssertTrue(box.waitForExistence(timeout: Self.timeout), "Opacity has no box for its value")
        reveal(box)
        XCTAssertEqual(box.value as? String, "100")

        enter("40", in: box)
        XCTAssertEqual(slider.normalizedSliderPosition, 0.4, accuracy: 0.02, "Typing 40 did not move the slider")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Change Opacity")
        app.typeKey("z", modifierFlags: .command)
        expect(box, toRead: "100")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Add Speedometer", "Typing a value was more than one undo step")

        enter("250", in: box)
        expect(box, toRead: "100")
        XCTAssertEqual(slider.normalizedSliderPosition, 1, accuracy: 0.02)
    }

    /// ↑/↓ in the box step the value, each press its own edit.
    @MainActor
    func testArrowKeysInTheBoxStepTheValue() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        let box = app.textFields["object.opacity.value"]
        XCTAssertTrue(box.waitForExistence(timeout: Self.timeout))
        reveal(box)
        box.click()
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])
        expect(box, toRead: "98")
        XCTAssertEqual(app.sliders["object.opacity"].normalizedSliderPosition, 0.98, accuracy: 0.01)
    }

    /// Now at takes a typed value, and Middle puts it back in the middle as one undoable step;
    /// the button is off when it is already there.
    @MainActor
    func testMiddlePutsNowBackInTheMiddle() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Graph")
        let box = app.textFields["graph.nowAt.value"]
        let middle = app.buttons["graph.nowAt.middle"]
        XCTAssertTrue(box.waitForExistence(timeout: Self.timeout), "Now at has no box for its value")
        reveal(middle)
        XCTAssertEqual(box.value as? String, "50")
        XCTAssertFalse(middle.isEnabled, "Middle is on while now is already in the middle")

        enter("20", in: box)
        XCTAssertEqual(app.sliders["graph.nowAt"].normalizedSliderPosition, 0.2, accuracy: 0.02)
        XCTAssertTrue(middle.isEnabled)
        middle.click()
        expect(box, toRead: "50")
        XCTAssertFalse(middle.isEnabled)
        app.typeKey("z", modifierFlags: .command)
        expect(box, toRead: "20")
    }

    /// Selects what the box holds, types over it and leaves with Tab, which commits it and moves
    /// focus on so ⌘Z undoes the project rather than the typing.
    @MainActor
    private func enter(_ text: String, in box: XCUIElement) {
        box.click()
        app.typeKey("a", modifierFlags: .command)
        app.typeText(text + "\t")
    }
}
