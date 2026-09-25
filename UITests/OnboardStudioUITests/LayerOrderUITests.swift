import XCTest

// ci-shard: 3
/// Putting overlays in front of or behind each other (#277): the Arrange menu, and dragging rows
/// in the sidebar, which lists the front first.
final class LayerOrderUITests: OnboardStudioUITestCase {
    /// Whether `upper`'s sidebar row is above `lower`'s: in front of it.
    @MainActor
    func isInFront(_ upper: String, of lower: String) -> Bool {
        sidebarObject(upper).frame.minY < sidebarObject(lower).frame.minY
    }

    @MainActor
    func testArrangeMenuMovesTheSelection() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        toolbarMenu("toolbar.addObject", "Lap Timer")
        XCTAssertTrue(sidebarObject("Timer").waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(isInFront("Timer", of: "Speedometer"), "The newest object is not in front")

        sidebarObject("Speedometer").click()
        menu("Arrange", "Bring to Front")
        XCTAssertTrue(isInFront("Speedometer", of: "Timer"))
        XCTAssertEqual(undoRedoTitles().undo, "Undo Bring to Front")
        app.menuBarItems["Arrange"].click()
        XCTAssertFalse(
            app.menuBarItems["Arrange"].menus.menuItems["Bring Forward"].isEnabled, "Forward from the front")
        app.typeKey(.escape, modifierFlags: [])

        // ⌥⇧⌘B: one step back.
        app.typeKey("b", modifierFlags: [.command, .shift, .option])
        XCTAssertTrue(isInFront("Timer", of: "Speedometer"))
        XCTAssertEqual(undoRedoTitles().undo, "Undo Send Backward")
    }

    @MainActor
    func testDraggingARowReordersTheStack() throws {
        launch()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        toolbarMenu("toolbar.addObject", "Lap Timer")
        let timer = sidebarObject("Timer")
        XCTAssertTrue(timer.waitForExistence(timeout: Self.timeout))
        let below = sidebarObject("Speedometer").coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.2))
        timer.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.5, thenDragTo: below, withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertTrue(isInFront("Speedometer", of: "Timer"), "The drag did not send the timer back")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Change Layer Order")
    }
}
