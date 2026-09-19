import XCTest

/// J1: the app explains itself on first launch.
final class FirstLaunchUITests: OverlayGenUITestCase {
    @MainActor
    func testWelcomeAndGettingStarted() throws {
        launch()
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["welcome.addVideo"].exists)
        XCTAssertTrue(app.buttons["Open the Sample Project"].exists)
        XCTAssertTrue(app.staticTexts["Getting Started"].exists)
        for step in ["Add a video", "Add the data", "Add gauges", "Export"] {
            XCTAssertTrue(app.staticTexts[step].exists, "Getting Started lists “\(step)”")
        }
        // Nothing to lay out, sync or export yet.
        XCTAssertFalse(app.buttons["toolbar.sync"].isEnabled)
        XCTAssertFalse(app.buttons["toolbar.export"].isEnabled)
        XCTAssertTrue(app.buttons["toolbar.addVideo"].isEnabled)
    }

    @MainActor
    func testTourStepsThroughAndCanBeRepeated() throws {
        launch(tourSeen: false)
        let step = app.staticTexts["tour.step"]
        XCTAssertTrue(step.waitForExistence(timeout: Self.timeout), "The first-run tour did not appear")
        expect(step, toRead: "1 of 3")
        app.buttons["tour.next"].click()
        expect(step, toRead: "2 of 3")
        app.buttons["tour.next"].click()
        expect(step, toRead: "3 of 3")
        XCTAssertEqual(app.buttons["tour.next"].label, "Done")
        app.buttons["tour.next"].click()
        XCTAssertTrue(step.waitForNonExistence(timeout: Self.timeout))
        // Help ▸ Take the Tour brings it back; Skip dismisses it at once.
        menu("Help", "Take the Tour")
        XCTAssertTrue(step.waitForExistence(timeout: Self.timeout))
        expect(step, toRead: "1 of 3")
        app.buttons["tour.skip"].click()
        XCTAssertTrue(step.waitForNonExistence(timeout: Self.timeout))
    }

    @MainActor
    func testShortcutsWindowOpens() throws {
        launch()
        menu("Help", "Keyboard Shortcuts")
        XCTAssertTrue(app.windows["Keyboard Shortcuts"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["Add video"].exists)
    }
}

/// J8: timeline zoom, snapping and the transport.
final class TimelineUITests: OverlayGenUITestCase {
    @MainActor
    func testZoomSnapAndTransport() throws {
        launch()
        addFixtureVideo()
        // The lane shows the video and the ruler spans its 3 s.
        XCTAssertTrue(app.staticTexts["test-3s"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["0:03"].exists)
        let fit = app.buttons["transport.fit"]
        XCTAssertFalse(fit.isEnabled, "Zoom to fit is a no-op at 1×")
        app.buttons["transport.zoomIn"].click()
        XCTAssertTrue(fit.isEnabled)
        app.typeKey("=", modifierFlags: .command)
        fit.click()
        XCTAssertFalse(fit.isEnabled, "Zoom to fit returns to 1×")
        app.buttons["transport.snap"].click()
        app.buttons["transport.snap"].click()
        // Transport: one frame forward is 1/30 s; Go to start returns to zero.
        expect(transportTime, toRead: "0:00.00")
        app.buttons["transport.stepForward"].click()
        expect(transportTime, toRead: "0:00.03")
        app.buttons["transport.stepForward"].click()
        expect(transportTime, toRead: "0:00.07")
        app.buttons["transport.stepBack"].click()
        expect(transportTime, toRead: "0:00.03")
        app.buttons["transport.start"].click()
        expect(transportTime, toRead: "0:00.00")
    }
}
