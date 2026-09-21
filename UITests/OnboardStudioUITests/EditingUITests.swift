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

    /// #131: nudging the video earlier than the project's start used to fail the whole compile
    /// with an AVFoundation `-11800`, because nothing can be inserted at a negative time. The part
    /// before the start is dropped instead, and the panel says how much.
    @MainActor
    func testNudgingTheVideoBeforeTheStartIsAllowedAndExplained() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        app.buttons["toolbar.sync"].click()
        XCTAssertTrue(app.buttons["sync.done"].waitForExistence(timeout: Self.timeout))

        let readout = app.staticTexts["sync.panelOffset.video"]
        XCTAssertTrue(readout.waitForExistence(timeout: Self.timeout), "No video offset readout")
        // One press from zero is enough to go negative, which is all it ever took.
        app.buttons["sync.video-1s"].click()
        expect(readout, toContain: "unused")

        // The project is still usable: the compile that used to fail now succeeds, so the sidebar
        // and the timeline still respond.
        sidebarInput("test-3s").click()
        let offset = app.textFields["sync.offset"]
        XCTAssertTrue(offset.waitForExistence(timeout: Self.timeout), "The window stopped responding")
        expect(offset, toRead: "-1")

        // And it is reversible: the nudge back puts the offset exactly where it was.
        app.buttons["sync.video+1s"].click()
        expect(offset, toRead: "0")
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

    /// #64: the Sector Times panel is reachable from the Add Object menu and its comparison is
    /// switchable, which is the only way a user meets sector timing in the app.
    @MainActor
    func testSectorTimesPanelIsAddedAndCompared() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Sector Times")
        XCTAssertTrue(sidebarObject("Sector Times").waitForExistence(timeout: Self.timeout))
        // The panel compares with the best sector by default; switch it to the lap before.
        choose("Previous lap", inPopUpShowing: "Best sector")
        XCTAssertTrue(
            app.popUpButtons.matching(NSPredicate(format: "value == 'Previous lap'")).firstMatch.waitForExistence(
                timeout: Self.timeout),
            "The sector comparison did not change")
    }

    /// #86: ↑/↓ step the number field that has focus, so a value can be adjusted slightly
    /// without selecting the text and retyping it.
    ///
    /// Every assertion is at the end on purpose. Polling the element between keystrokes — which
    /// is what an `expect` after each press does — costs the field its key handling, and reads
    /// as "only the first press works" when the app is in fact fine.
    @MainActor
    func testArrowKeysStepTheFocusedNumberField() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        toolbarMenu("toolbar.addObject", "Speedometer")
        XCTAssertTrue(sidebarObject("Speedometer").waitForExistence(timeout: Self.timeout))

        let x = app.textFields["object.x"]
        XCTAssertTrue(x.waitForExistence(timeout: Self.timeout), "No X field in the inspector")
        reveal(x)
        guard let start = Double((x.value as? String) ?? "") else {
            return XCTFail("X did not read as a number: \(x.value ?? "nil")")
        }

        x.click()
        for _ in 0..<3 { app.typeKey(.upArrow, modifierFlags: []) }
        expectNumber(x, toBe: start + 3, "↑ should add one on every press, not just the first")

        let y = app.textFields["object.y"]
        reveal(y)
        y.click()
        for _ in 0..<2 { app.typeKey(.downArrow, modifierFlags: []) }
        guard let yStart = Double((y.value as? String) ?? "") else { return XCTFail("Y unreadable") }
        XCTAssertLessThan(yStart, 100, "Y should have come down")

        // The steps are ordinary edits, so undo walks back through them.
        app.typeKey("z", modifierFlags: .command)
        app.typeKey("z", modifierFlags: .command)
        expectNumber(x, toBe: start + 3, "undo should not have touched X yet")
    }

    /// Compares numerically: the field formats to as many as three decimals, so the printed text
    /// depends on where the value started.
    @MainActor
    private func expectNumber(
        _ element: XCUIElement, toBe expected: Double, _ message: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let predicate = NSPredicate { value, _ in
            guard let read = Double(((value as? XCUIElement)?.value as? String) ?? "") else { return false }
            return abs(read - expected) < 0.001
        }
        let result = XCTWaiter().wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: Self.timeout)
        XCTAssertEqual(
            result, .completed, "\(message): expected \(expected), got \(element.value ?? "nil")",
            file: file, line: line)
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
        XCTAssertEqual(segments.count, 0, "No segments before adding one")
        // The lane is not there at all until there is a segment to put in it (#105): a project
        // with none used to show a full-width grey bar labelled "Start".
        XCTAssertFalse(app.staticTexts["Start"].exists, "No segment lane before there are segments")
        toolbarMenu("toolbar.layout", "Add Segment at Playhead")
        XCTAssertTrue(segments.firstMatch.waitForExistence(timeout: Self.timeout), "Segment on the strip")
        XCTAssertTrue(app.staticTexts["Segment"].waitForExistence(timeout: Self.timeout), "Segment inspector")
        // Not asserting the "Start" span here on purpose: two frame steps in leaves it a couple of
        // pixels wide, so whether its label is in the tree depends on the fixture's duration.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(segments.firstMatch.waitForNonExistence(timeout: Self.timeout), "Undo removes the segment")
        XCTAssertTrue(app.staticTexts["Start"].waitForNonExistence(timeout: Self.timeout), "And the lane with it")
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
