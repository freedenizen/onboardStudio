import XCTest

// ci-shard: 1
/// J25: two laps side by side, the compared one kept level by distance (#154).
final class CompareLapsUITests: OnboardStudioUITestCase {
    @MainActor
    func testComparingLapsLaysOutBothAndStoppingKeepsTheLap() throws {
        launch()
        addFixtureVideo()
        addFixtureData()

        menu("Project", "Compare Laps…")
        let compare = app.buttons["compare.ok"]
        XCTAssertTrue(compare.waitForExistence(timeout: Self.timeout), "No Compare Laps sheet")
        // The sheet offers two different laps to start with, so Compare is ready to press.
        XCTAssertTrue(compare.isEnabled, "Compare is not enabled with the laps chosen for you")
        compare.click()
        for label in ["Lap Picture", "Compared Lap Picture", "Lap Timer", "Compared Lap Timer", "Delta"] {
            XCTAssertTrue(sidebarObject(label).waitForExistence(timeout: Self.timeout), "No \(label)")
        }

        // One undo step puts the project back as it was.
        menu("Edit", "Undo Compare Laps")
        XCTAssertTrue(waitForNonExistence(sidebarObject("Compared Lap Picture")), "Undo left the comparison")
        menu("Edit", "Redo Compare Laps")
        XCTAssertTrue(sidebarObject("Compared Lap Picture").waitForExistence(timeout: Self.timeout))

        // Stopping takes the compared lap away and leaves the lap playing.
        menu("Project", "Stop Comparing Laps")
        XCTAssertTrue(waitForNonExistence(sidebarObject("Compared Lap Picture")), "The compared lap stayed")
        XCTAssertTrue(sidebarObject("Lap Picture").exists, "Stopping also took the lap playing")
    }

    func waitForNonExistence(_ element: XCUIElement) -> Bool {
        element.waitForNonExistence(timeout: Self.timeout)
    }
}
