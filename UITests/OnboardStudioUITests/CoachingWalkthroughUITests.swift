import XCTest

// ci-shard: 3
/// J57: be coached through a lap (#458). The Coaching window opens on a walkthrough — the lap in a
/// sentence, then its biggest losses one corner at a time with the whole of what to try, then a
/// plan of the corners the driver chose — and the full analysis is a click away as All Corners.
final class CoachingWalkthroughUITests: OnboardStudioUITestCase {
    private var step: XCUIElement { app.staticTexts["coaching.walkthrough.step"] }
    private var next: XCUIElement { app.buttons["coaching.walkthrough.next"] }
    private var back: XCUIElement { app.buttons["coaching.walkthrough.back"] }

    @MainActor
    func testTheLapItsCornersAndAPlanOneStepAtATime() throws {
        launch()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")
        menu("Project", "Coaching…")

        // The lap: chosen under Change…, said in a sentence.
        let change = app.buttons["coaching.walkthrough.change"]
        XCTAssertTrue(change.waitForExistence(timeout: Self.timeout * 2), "The window did not open on the walkthrough")
        expect(step, toRead: "The Lap")
        change.click()
        let lapPicker = app.popUpButtons["coaching.lap"]
        XCTAssertTrue(lapPicker.waitForExistence(timeout: Self.timeout), "No lap to choose under Change…")
        choosePopUpItem("Lap 2 — 0:44.60", in: lapPicker)
        app.typeKey(.escape, modifierFlags: [])
        let headline = app.staticTexts["coaching.walkthrough.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: Self.timeout * 2), "No sentence for the lap")
        expect(headline, toContain: "Lap 2")

        // The slow lap loses time in two corners: one step each, what to try in full.
        next.click()
        let first = try cornerStep(number: 1, of: 2)
        // Watch says when nothing shows the corner: the project has no video (#516).
        XCTAssertTrue(
            app.staticTexts["coaching.walkthrough.noVideo"].waitForExistence(timeout: Self.timeout),
            "The corner does not say there is no video of it")
        XCTAssertFalse(app.buttons["coaching.walkthrough.watch"].exists, "Watch with nothing to play")
        let tryIt = app.checkBoxes["coaching.walkthrough.try"]
        XCTAssertTrue(tryIt.exists, "No Try this next time")
        XCTAssertEqual(tryIt.value as? Int, 1, "A corner is not chosen to try to begin with")
        tryIt.click()
        XCTAssertEqual(tryIt.value as? Int, 0)

        // Back and forth keeps what was chosen.
        back.click()
        expect(step, toRead: "The Lap")
        next.click()
        XCTAssertEqual(try cornerStep(number: 1, of: 2), first)
        XCTAssertEqual(tryIt.value as? Int, 0, "Going back forgot the choice")
        next.click()
        let second = try cornerStep(number: 2, of: 2)
        XCTAssertNotEqual(second, first, "The second corner's advice is the first's")

        // The plan: only the corner still chosen, kept with the project and undoable.
        next.click()
        expect(step, toRead: "Your Plan")
        let experiment = app.textFields["coaching.walkthrough.experiment.0"]
        XCTAssertTrue(experiment.waitForExistence(timeout: Self.timeout), "No experiment in the plan")
        XCTAssertEqual(experiment.value as? String, second, "The plan is not the chosen corner's advice")
        XCTAssertFalse(app.textFields["coaching.walkthrough.experiment.1"].exists, "An unchosen corner is planned")
        app.buttons["coaching.walkthrough.savePlan"].click()
        XCTAssertTrue(
            app.descendants(matching: .any)["coaching.walkthrough.saved"].waitForExistence(timeout: Self.timeout),
            "The plan was not saved")
        XCTAssertEqual(undoRedoTitles().undo, "Undo Make Plan")

        // All Corners shows the same plan, beside every corner.
        showAllCorners()
        XCTAssertTrue(app.staticTexts["coaching.headline"].waitForExistence(timeout: Self.timeout), "No All Corners")
        let planned = app.textFields["coaching.plan.experiment.1"]
        XCTAssertTrue(planned.waitForExistence(timeout: Self.timeout), "All Corners does not show the plan")
        XCTAssertEqual(planned.value as? String, second)
        XCTAssertFalse(app.textFields["coaching.plan.experiment.2"].exists)
    }

    /// From the Logbook, with no project: the same walkthrough, and a plan step that says where it
    /// can — or here cannot — keep the plan.
    @MainActor
    func testASessionIsWalkedThroughWithNoProjectOpen() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout))
        search.click()
        search.typeText("coaching-laps")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let row = table.descendants(matching: .any).matching(
            NSPredicate(
                format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
                XCUIElement.ElementType.outlineRow.rawValue)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No coaching session in the logbook")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let coach = app.buttons["logbook.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.timeout), "No Coach… in the detail")
        coach.click()

        XCTAssertTrue(step.waitForExistence(timeout: Self.timeout * 2), "The window did not open on the walkthrough")
        expect(step, toRead: "The Lap")
        XCTAssertEqual(projectWindows.count, 0, "Coaching opened a project")
        // The slow lap, which has corners to go through.
        app.buttons["coaching.walkthrough.change"].click()
        let lapPicker = app.popUpButtons["coaching.lap"]
        XCTAssertTrue(lapPicker.waitForExistence(timeout: Self.timeout), "No lap to choose under Change…")
        choosePopUpItem("Lap 2 — 0:44.60", in: lapPicker)
        app.typeKey(.escape, modifierFlags: [])
        expect(app.staticTexts["coaching.walkthrough.headline"], toContain: "Lap 2")
        next.click()
        // The fixture day has no clip of this session: nothing to watch, and it says so (#516).
        XCTAssertTrue(
            app.staticTexts["coaching.walkthrough.noVideo"].waitForExistence(timeout: Self.timeout),
            "A corner from the Logbook does not say there is no video of it")
        for _ in 0..<6 where next.exists { next.click() }
        expect(step, toRead: "Your Plan")
        // The fixture's circuit is not one the logbook knows: it says so rather than pretending.
        let explanation = app.staticTexts.matching(NSPredicate(format: "value CONTAINS 'does not know'")).firstMatch
        XCTAssertTrue(explanation.exists, "The plan step does not say why the plan cannot be kept")
        XCTAssertFalse(app.buttons["coaching.walkthrough.savePlan"].isEnabled, "Save Plan with nowhere to keep it")
    }

    /// The corner step's "Turn N · number of count", and its suggestion, which it returns.
    @MainActor
    private func cornerStep(number: Int, of count: Int, file: StaticString = #filePath, line: UInt = #line) throws
        -> String
    {
        let corner = app.staticTexts["coaching.walkthrough.corner"]
        XCTAssertTrue(corner.waitForExistence(timeout: Self.timeout), "No corner step", file: file, line: line)
        expect(step, toContain: "\(number) of \(count)")
        let suggestion = app.staticTexts["coaching.walkthrough.suggestion"]
        XCTAssertTrue(suggestion.exists, "No suggestion", file: file, line: line)
        let text = try XCTUnwrap(suggestion.value as? String, file: file, line: line)
        XCTAssertFalse(text.isEmpty, "An empty suggestion", file: file, line: line)
        XCTAssertFalse(text.hasSuffix("…"), "The suggestion is cut off: \(text)", file: file, line: line)
        return text
    }
}
