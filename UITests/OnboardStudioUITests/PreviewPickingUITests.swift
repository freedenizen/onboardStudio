import XCTest

// ci-shard: 1
/// A click on the picture does not pick the video under everything, unless the video was chosen
/// first (#278).
final class PreviewPickingUITests: OnboardStudioUITestCase {
    var projectInspector: XCUIElement { app.popUpButtons["project.outputSize"] }
    var videoInspector: XCUIElement { app.staticTexts["Video Layer"] }

    @MainActor
    func testAClickOnThePictureLeavesTheVideoAloneUntilItIsChosen() throws {
        launch()
        addFixtureVideo()
        XCTAssertTrue(sidebarObject("Camera").waitForExistence(timeout: Self.timeout))
        app.typeKey("a", modifierFlags: [.command, .shift])
        let preview = app.descendants(matching: .any)["preview"]
        XCTAssertTrue(preview.waitForExistence(timeout: Self.timeout))

        // Nothing but the video under the pointer: nothing is selected.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).click()
        XCTAssertTrue(projectInspector.waitForExistence(timeout: Self.timeout))
        XCTAssertFalse(videoInspector.exists, "A click on the picture selected the video")

        // Chosen in the sidebar, it stays selected when its picture is clicked, so it can be moved.
        sidebarObject("Camera").click()
        XCTAssertTrue(videoInspector.waitForExistence(timeout: Self.timeout))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.3)).click()
        XCTAssertTrue(videoInspector.waitForExistence(timeout: Self.timeout), "The chosen video was dropped")
    }
}
