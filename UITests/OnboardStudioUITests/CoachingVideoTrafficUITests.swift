import XCTest

// ci-shard: 2
/// J67, step 4: the Coaching window reads the session's onboard video for a car close ahead on
/// request (#573). Its own class so it runs on the lightest shard.
final class CoachingVideoTrafficUITests: OnboardStudioUITestCase {
    /// The video is read for a car close ahead on request (#573): the window offers it while the
    /// session's video has not been read, shows the reading, and says when it is done.
    @MainActor
    func testTheVideoIsReadForTrafficOnRequest() throws {
        launch()
        testing("Add Fixture Video")
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")
        menu("Project", "Coaching…")
        let find = app.buttons["coaching.findTraffic"]
        XCTAssertTrue(find.waitForExistence(timeout: Self.timeout * 2), "No offer to read the video for traffic")
        find.click()
        // The fixture is three seconds of test picture: read in a moment, with no car in it.
        XCTAssertTrue(
            app.staticTexts["coaching.findTraffic.done"].waitForExistence(timeout: Self.timeout * 3),
            "The video was not read")
        XCTAssertFalse(find.exists, "Still offering to read a video already read")
    }
}
