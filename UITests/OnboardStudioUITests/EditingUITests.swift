import XCTest

/// J3: start from a template, then add the media; files are never added twice.
final class TemplateUITests: OnboardStudioUITestCase {
    @MainActor
    func testNewFromTemplateThenMedia() throws {
        launch()
        menu("File", "New from Template", "Classic Dash")
        // The new document lists the template's objects before any input exists.
        XCTAssertTrue(sidebarObject("Speed").waitForExistence(timeout: Self.timeout), "Template objects missing")
        for label in ["RPM", "Map", "G", "Lap", "Best", "Gear", "Camera"] {
            XCTAssertTrue(sidebarObject(label).exists, "Template object “\(label)”")
        }
        addFixtureVideo()
        addFixtureData()
        // The gauges bind to the data file and the camera object to the video.
        sidebarObject("Speed").click()
        XCTAssertTrue(app.staticTexts["Speedometer"].waitForExistence(timeout: Self.timeout))
        let data = app.popUpButtons.matching(NSPredicate(format: "value == 'racerender-basic'")).firstMatch
        XCTAssertTrue(data.waitForExistence(timeout: Self.timeout), "Speedometer not bound to the data file")
        // The template's camera object took the video: no second, duplicate camera object was added.
        XCTAssertEqual(app.staticTexts.matching(identifier: "object.Camera").count, 1, "One camera object")
        sidebarObject("Camera").click()
        XCTAssertTrue(app.staticTexts["Video Layer"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["test-3s"].exists, "One bar on the timeline")
    }

    @MainActor
    func testAddingTheSameFileTwiceIsRefused() throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Video Again")
        expectStatus(containing: "already part of")
        XCTAssertEqual(app.staticTexts.matching(identifier: "input.test-3s").count, 1, "Video listed once")
        // A different recording is its own input: its own sidebar row and its own timeline bar,
        // so it can be moved and trimmed on its own. It used to be folded in as extra clips.
        testing("Add Second Fixture Video")
        XCTAssertTrue(sidebarInput("test-rot180").waitForExistence(timeout: Self.timeout), "Second recording listed")
        XCTAssertEqual(app.staticTexts.matching(identifier: "input.test-3s").count, 1)
        XCTAssertTrue(app.staticTexts["test-rot180"].exists, "Second bar on the timeline")
        sidebarInput("test-3s").click()
        XCTAssertFalse(app.staticTexts["test-rot180.mp4"].exists, "Not a clip of the first recording")
    }
}

/// J4: the manual sync wizard.
final class SyncUITests: OnboardStudioUITestCase {
    /// #76: manual sync is a panel under the preview, not a sheet over it. Each nudge applies
    /// straight away, and the rest of the window stays live so the picture can be judged while
    /// nudging — the loop the modal sheet made impossible.
    @MainActor
    func testSyncPanelNudgesLiveAndLeavesTheWindowUsable() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        app.buttons["toolbar.sync"].click()
        XCTAssertTrue(app.buttons["sync.done"].waitForExistence(timeout: Self.timeout), "No sync panel")

        // A whole second, then a single frame: at the project's 30 fps that is 1 + 1/30.
        app.buttons["sync.data+1s"].click()
        app.buttons["sync.data+1f"].click()

        // Clicking the sidebar with the panel open is the point: a sheet would have blocked it.
        sidebarInput("racerender-basic").click()
        let offset = app.textFields["sync.offset"]
        XCTAssertTrue(offset.waitForExistence(timeout: Self.timeout), "The panel is still modal")
        expect(offset, toRead: "1.033")

        // Every nudge is its own undo step, so a wrong move costs one ⌘Z rather than the lot.
        app.typeKey("z", modifierFlags: .command)
        expect(offset, toRead: "1")
        app.typeKey("z", modifierFlags: .command)
        expect(offset, toRead: "0")
    }

    /// The video moves against the data as well, which is the right way round when the data is
    /// trustworthy and the camera started late.
    @MainActor
    func testSyncPanelAlsoMovesTheVideo() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        app.buttons["toolbar.sync"].click()
        XCTAssertTrue(app.buttons["sync.done"].waitForExistence(timeout: Self.timeout))
        app.buttons["sync.video+1s"].click()

        sidebarInput("test-3s").click()
        let offset = app.textFields["sync.offset"]
        XCTAssertTrue(offset.waitForExistence(timeout: Self.timeout))
        expect(offset, toRead: "1")
    }
}

/// J5 and J6: objects and their inspectors.
final class ObjectEditingUITests: OnboardStudioUITestCase {
    @MainActor
    func testAddRenameRetuneHideDeleteUndo() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        XCTAssertTrue(sidebarObject("Speedometer").waitForExistence(timeout: Self.timeout))
        // Rename in the inspector; the sidebar follows.
        let label = app.textFields["object.label"]
        XCTAssertTrue(label.waitForExistence(timeout: Self.timeout))
        label.click()
        app.typeKey("a", modifierFlags: .command)
        label.typeText("Speedo\n")
        XCTAssertTrue(sidebarObject("Speedo").waitForExistence(timeout: Self.timeout), "Rename not reflected")
        // Speed unit mph → kph.
        choose("kph", inPopUpShowing: "mph")
        XCTAssertTrue(
            app.popUpButtons.matching(NSPredicate(format: "value == 'kph'")).firstMatch.waitForExistence(
                timeout: Self.timeout))
        // Hide and show from the sidebar.
        app.buttons["Hide Speedo"].click()
        XCTAssertTrue(app.buttons["Show Speedo"].waitForExistence(timeout: Self.timeout))
        app.buttons["Show Speedo"].click()
        XCTAssertTrue(app.buttons["Hide Speedo"].waitForExistence(timeout: Self.timeout))
        // Delete, undo, redo.
        menu("Project", "Delete Selected Object")
        XCTAssertTrue(sidebarObject("Speedo").waitForNonExistence(timeout: Self.timeout))
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(sidebarObject("Speedo").waitForExistence(timeout: Self.timeout), "Undo restores the object")
        app.typeKey("z", modifierFlags: [.command, .shift])
        XCTAssertTrue(sidebarObject("Speedo").waitForNonExistence(timeout: Self.timeout), "Redo removes it again")
    }

    @MainActor
    func testIndicatorLightAsksForAChannelAndSuggestsAThreshold() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "ABS Light")
        XCTAssertTrue(sidebarObject("Indicator").waitForExistence(timeout: Self.timeout))
        // The RaceRender fixture has no ABS channel, so the light starts unbound and says so.
        XCTAssertTrue(app.staticTexts["This object needs a channel."].waitForExistence(timeout: Self.timeout))
        choose("speed", inPopUpShowing: "Choose a channel…")
        XCTAssertTrue(app.staticTexts["This object needs a channel."].waitForNonExistence(timeout: Self.timeout))
        // The inspector shows the channel's range and suggests a threshold from it.
        let suggest = app.buttons["indicator.suggest"]
        XCTAssertTrue(suggest.waitForExistence(timeout: Self.timeout), "No threshold suggestion")
        let suggested = suggest.label.replacingOccurrences(of: "Suggest ", with: "")
        suggest.click()
        expect(app.textFields["indicator.threshold"], toRead: suggested)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'In this file:'")).firstMatch.exists)
    }
}

/// J7: a second camera, layouts and segments.
final class MultiCameraUITests: OnboardStudioUITestCase {
    @MainActor
    func testSecondCameraLayoutsAndSegments() throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Camera")
        XCTAssertTrue(sidebarInput("stereo-1s").waitForExistence(timeout: Self.timeout), "Second lane")
        XCTAssertTrue(sidebarObject("stereo-1s").waitForExistence(timeout: Self.timeout), "Picture-in-picture object")
        XCTAssertTrue(app.staticTexts["stereo-1s"].exists, "Second bar on the timeline")
        // Side by side puts the main camera in the left half.
        toolbarMenu("toolbar.layout", "Side by side")
        sidebarObject("Camera").click()
        XCTAssertTrue(app.staticTexts["Position & Size (% of frame)"].waitForExistence(timeout: Self.timeout))
        let width = app.textFields.matching(NSPredicate(format: "value == '50'")).firstMatch
        XCTAssertTrue(width.waitForExistence(timeout: Self.timeout), "Main camera is half the frame wide")
        // A segment at the playhead: the strip and the inspector show it.
        app.buttons["transport.stepForward"].click()
        app.buttons["transport.stepForward"].click()
        let segments = app.staticTexts.matching(NSPredicate(format: "value BEGINSWITH 'Segment '"))
        XCTAssertEqual(segments.count, 0, "Only the implicit start segment before adding one")
        toolbarMenu("toolbar.layout", "Add Segment at Playhead")
        XCTAssertTrue(segments.firstMatch.waitForExistence(timeout: Self.timeout), "Segment on the strip")
        XCTAssertTrue(app.staticTexts["Segment"].waitForExistence(timeout: Self.timeout), "Segment inspector")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(segments.firstMatch.waitForNonExistence(timeout: Self.timeout), "Undo removes the segment")
    }
}

/// J9: open, edit, save and reopen a project.
final class ProjectUITests: OnboardStudioUITestCase {
    @MainActor
    func testOpenEditSaveReopen() throws {
        launch()
        testing("Open Fixture Project")
        let window = app.windows["slice.onboardproj"]
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout), "Fixture project window")
        XCTAssertTrue(sidebarInput("Camera").waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(sidebarObject("Speed").waitForExistence(timeout: Self.timeout))
        app.buttons["Hide Speed"].click()
        XCTAssertTrue(app.buttons["Show Speed"].waitForExistence(timeout: Self.timeout))
        app.typeKey("s", modifierFlags: .command)
        sleep(1)
        app.typeKey("w", modifierFlags: .command)
        XCTAssertTrue(window.waitForNonExistence(timeout: Self.timeout), "Closed without a save prompt")
        testing("Open Fixture Project")
        XCTAssertTrue(window.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["Show Speed"].waitForExistence(timeout: Self.timeout), "Hidden state was saved")
    }
}
