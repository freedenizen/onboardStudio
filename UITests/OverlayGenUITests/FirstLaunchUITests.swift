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

/// J1: the welcome window offers a blank project, a template, or an existing project.
final class LauncherUITests: OverlayGenUITestCase {
    @MainActor
    func testWelcomeWindowStartsABlankProjectAndCanBeReopened() throws {
        launch(launcher: true)
        let welcome = app.windows["Welcome to OverlayGen"]
        XCTAssertTrue(welcome.waitForExistence(timeout: Self.timeout), "No welcome window at launch")
        XCTAssertFalse(app.windows["Untitled"].exists, "No project until the user asks for one")
        XCTAssertFalse(app.sheets.firstMatch.exists || app.dialogs.firstMatch.exists, "No Open panel at launch")
        for identifier in ["launcher.newBlank", "launcher.open", "launcher.template.Classic Dash", "launcher.sample"] {
            // The sample project is a link-style button, which accessibility reports as a link.
            let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(element.exists, "Welcome window offers \(identifier)")
        }
        app.buttons["launcher.newBlank"].click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: Self.timeout), "Blank project")
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(welcome.waitForNonExistence(timeout: Self.timeout), "The welcome window steps aside")
        menu("Help", "Welcome to OverlayGen")
        XCTAssertTrue(welcome.waitForExistence(timeout: Self.timeout), "Help ▸ Welcome brings it back")
    }

    @MainActor
    func testWelcomeWindowStartsFromATemplate() throws {
        launch(launcher: true)
        let card = app.buttons["launcher.template.Glass Cockpit"]
        XCTAssertTrue(card.waitForExistence(timeout: Self.timeout))
        card.click()
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: Self.timeout))
        for label in ["Wheel", "Speed", "RPM", "Fade"] {
            XCTAssertTrue(sidebarObject(label).waitForExistence(timeout: Self.timeout), "Template object “\(label)”")
        }
        XCTAssertTrue(app.windows["Welcome to OverlayGen"].waitForNonExistence(timeout: Self.timeout))
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
