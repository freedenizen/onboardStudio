import XCTest

// ci-shard: 2
/// J26: steady a shaky helmet video (#262). The fixture video has no motion record, so this drives
/// what such a video shows: the control there, disabled, and the reason beside it.
final class StabilisationUITests: OnboardStudioUITestCase {
    @MainActor
    func testAVideoWithoutMotionDataSaysSo() throws {
        launch()
        addFixtureVideo()
        sidebarInput("test-3s").click()
        let steady = app.popUpButtons["stabilisation.method"]
        XCTAssertTrue(steady.waitForExistence(timeout: Self.timeout), "No Stabilisation control in the inspector")
        reveal(steady)
        XCTAssertFalse(steady.isEnabled, "Steady should be disabled for a video with no motion record")
        let reason = app.staticTexts.containing(NSPredicate(format: "value CONTAINS %@", "no camera motion record"))
        XCTAssertTrue(reason.firstMatch.waitForExistence(timeout: Self.timeout), "No explanation of why")
    }
}
