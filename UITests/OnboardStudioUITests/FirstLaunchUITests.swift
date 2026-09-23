import XCTest

/// J1: the app explains itself on first launch.
final class FirstLaunchUITests: OnboardStudioUITestCase {
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
final class LauncherUITests: OnboardStudioUITestCase {
    @MainActor
    func testWelcomeWindowStartsABlankProjectAndCanBeReopened() throws {
        launch(launcher: true)
        let welcome = app.windows["Welcome to Onboard Studio"]
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
        menu("Help", "Welcome to Onboard Studio")
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
        XCTAssertTrue(app.windows["Welcome to Onboard Studio"].waitForNonExistence(timeout: Self.timeout))
    }
}

/// J8: timeline zoom, snapping and the transport.
/// #54: markers on the timeline, and walking between them.
final class MarkerUITests: OnboardStudioUITestCase {
    @MainActor
    func testMarkersAreAddedListedAndJumpedBetween() throws {
        launch()
        addFixtureVideo()

        // M at the playhead, then move on and add a second one.
        menu("Marker", "Add Marker")
        XCTAssertTrue(
            app.staticTexts["markerRow.Marker 1"].waitForExistence(timeout: Self.timeout), "No marker in the list")
        menu("Playback", "Step Forward")
        menu("Playback", "Step Forward")
        menu("Marker", "Add Marker")
        XCTAssertTrue(app.staticTexts["markerRow.Marker 2"].waitForExistence(timeout: Self.timeout))

        // Walking back and forth reports the marker it lands on in the status line.
        menu("Marker", "Previous Marker")
        expectStatus(containing: "Marker 1")
        menu("Marker", "Next Marker")
        expectStatus(containing: "Marker 2")
        // Past the last one there is nowhere to go, and it says so rather than jumping to 0.
        menu("Marker", "Next Marker")
        expectStatus(containing: "No marker that way")

        // Deleting leaves the other, and undo brings it back.
        menu("Marker", "Delete Marker")
        XCTAssertTrue(app.staticTexts["markerRow.Marker 2"].waitForNonExistence(timeout: Self.timeout))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            app.staticTexts["markerRow.Marker 2"].waitForExistence(timeout: Self.timeout), "Undo did not restore it")
    }
}

/// #54: trimming a video to the playhead, with Resolve's ⇧[ / ⇧].
final class TrimUITests: OnboardStudioUITestCase {
    @MainActor
    func testTrimsAVideoToThePlayheadAndRefusesWhenItCannot() throws {
        launch()
        addFixtureVideo()
        sidebarInput("test-3s").click()

        // At the very start there is nothing before the playhead to drop, and saying so beats
        // silently doing nothing or trimming the clip away.
        menu("Project", "Trim Start to Playhead")
        expectStatus(containing: "Put the playhead inside")

        // Step a few frames in, then trim; the start position follows the playhead.
        for _ in 0..<10 { app.typeKey(".", modifierFlags: []) }
        menu("Project", "Trim Start to Playhead")
        expectStatus(containing: "Trimmed the start")

        let start = app.textFields["sync.startPosition"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout))
        XCTAssertNotEqual(start.value as? String, "0", "The start position did not move")

        app.typeKey("z", modifierFlags: .command)
        expect(start, toRead: "0")
    }
}

/// #51: the data file shows where its laps are, and the playhead can jump between them.
final class LapUITests: OnboardStudioUITestCase {
    @MainActor
    func testJumpsBetweenTheLapsOfTheDataFile() throws {
        launch()
        addFixtureVideo()
        addFixtureData()

        // The fixture's laps start at 0, 4 and 8 s of the data. Jumping reports the lap it lands
        // on, with its time.
        menu("Marker", "Next Lap")
        expectStatus(containing: "Lap 1")

        menu("Marker", "Previous Lap")
        expectStatus(containing: "Lap 0")

        // Before the first lap there is nowhere to go, and it says so rather than sitting silent.
        menu("Marker", "Previous Lap")
        expectStatus(containing: "No lap that way")
    }
}

/// #54: splitting a video at the playhead.
final class SplitUITests: OnboardStudioUITestCase {
    @MainActor
    func testSplitsAVideoIntoTwoHalvesThatSwapAtTheCut() throws {
        launch()
        addFixtureVideo()
        sidebarInput("test-3s").click()

        // On the very edge there is no second half to make, and it says so.
        menu("Project", "Split at Playhead")
        expectStatus(containing: "Put the playhead inside")

        for _ in 0..<20 { app.typeKey(".", modifierFlags: []) }
        menu("Project", "Split at Playhead")
        expectStatus(containing: "Split test-3s")

        // A second input, a second video object to show it, and a segment to swap them over —
        // without all three the second half would never appear on screen.
        XCTAssertTrue(sidebarInput("test-3s 2").waitForExistence(timeout: Self.timeout), "No second input")
        XCTAssertTrue(sidebarObject("Camera 2").waitForExistence(timeout: Self.timeout), "No second camera object")

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            sidebarInput("test-3s 2").waitForNonExistence(timeout: Self.timeout), "Undo left the split behind")
    }
}

/// #54: the data half — trimming and splitting a data file, not just a video.
final class DataEditingUITests: OnboardStudioUITestCase {
    @MainActor
    func testTrimsAndSplitsTheDataFile() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        sidebarInput("racerender-basic").click()

        // Trim the start to the playhead; the data's own trim field picks it up.
        for _ in 0..<15 { app.typeKey(".", modifierFlags: []) }
        menu("Project", "Trim Start to Playhead")
        expectStatus(containing: "Trimmed the start of racerender-basic")

        let trimStart = app.textFields["data.trimStart"]
        XCTAssertTrue(trimStart.waitForExistence(timeout: Self.timeout), "No data trim field")
        reveal(trimStart)
        XCTAssertNotEqual(trimStart.value as? String, "", "The data trim did not move")

        app.typeKey("z", modifierFlags: .command)

        // Splitting a data file works the same way a video does, gauges and all.
        for _ in 0..<5 { app.typeKey(".", modifierFlags: []) }
        menu("Project", "Split at Playhead")
        expectStatus(containing: "Split racerender-basic")
        XCTAssertTrue(
            sidebarInput("racerender-basic 2").waitForExistence(timeout: Self.timeout), "No second data input")

        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(sidebarInput("racerender-basic 2").waitForNonExistence(timeout: Self.timeout))
    }
}

final class TimelineUITests: OnboardStudioUITestCase {
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

    /// #106: a click on a clip in the timeline puts the playhead where it landed, as well as
    /// selecting the clip, the way every editor does.
    @MainActor
    func testClickingAClipMovesThePlayhead() throws {
        launch()
        addFixtureVideo()
        let label = app.staticTexts["test-3s"]
        XCTAssertTrue(label.waitForExistence(timeout: Self.timeout))
        expect(transportTime, toRead: "0:00.00")
        // Well to the right of the clip's name, still on the clip.
        label.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.5)).withOffset(CGVector(dx: 250, dy: 0)).click()
        let moved = NSPredicate(format: "value != '0:00.00' AND value BEGINSWITH '0:0'")
        XCTAssertEqual(
            XCTWaiter().wait(for: [XCTNSPredicateExpectation(predicate: moved, object: transportTime)], timeout: 10),
            .completed, "The playhead stayed at \(transportTime.value ?? "nil")")
    }
}
