import XCTest

// ci-shard: 4
/// J61 and J62: what comes next, in a new project and in the Logbook (#451, #452). A project with
/// a file in it says its next step above the preview; the Logbook, where the app opens, has a
/// checklist of its own and a tour.
final class GettingStartedUITests: OnboardStudioUITestCase {
    private var nextStep: XCUIElement { app.staticTexts["nextStep.title"] }

    /// J61: a video in a new project, and the bar says the data comes next, with the button that
    /// adds it; Show All Steps puts the checklist in view; Hide takes both away, and Help ▸ Show
    /// Getting Started brings them back.
    @MainActor
    func testANewProjectSaysWhatComesNext() throws {
        launch()
        XCTAssertFalse(nextStep.exists, "An empty project has the welcome, not the bar")
        testing("Add Fixture Video")
        XCTAssertTrue(nextStep.waitForExistence(timeout: Self.timeout * 2), "No next step above the preview")
        expect(nextStep, toRead: "Next step: Add the data")
        XCTAssertEqual(app.buttons["nextStep.action"].label, "Add Data File…")

        app.buttons["nextStep.showAll"].click()
        let checklist = app.staticTexts["Getting Started"]
        XCTAssertTrue(checklist.waitForExistence(timeout: Self.timeout), "Show All Steps did not show the checklist")
        XCTAssertTrue(checklist.isHittable, "The checklist is not in view")

        app.buttons["nextStep.hide"].click()
        XCTAssertTrue(nextStep.waitForNonExistence(timeout: Self.timeout), "Hide left the bar")
        XCTAssertFalse(checklist.exists, "Hide left the checklist")
        menu("Help", "Show Getting Started")
        XCTAssertTrue(nextStep.waitForExistence(timeout: Self.timeout), "Show Getting Started did not bring it back")
    }

    /// J62: the Logbook's checklist, in the detail column while no session is chosen, ticks as the
    /// logbook fills and its buttons lead on; Help ▸ Take the Tour runs the Logbook's own tour.
    @MainActor
    func testTheLogbookHasAChecklistAndATour() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        let title = app.staticTexts["logbook.gettingStarted.title"]
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "No Getting Started in the Logbook")
        let first = app.descendants(matching: .any).matching(identifier: "logbook.gettingStarted.check.1").firstMatch
        expect(first, toRead: "To Do")
        XCTAssertFalse(app.buttons["logbook.gettingStarted.action.2"].isEnabled, "Show the Day with no day")

        testing("Add Fixture Track Day")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        app.buttons["trackday.done"].click()
        expect(first, toRead: "Done")
        // The fixtures come with no car: Show the Day goes to a day whose header has the field.
        app.buttons["logbook.gettingStarted.action.2"].click()
        XCTAssertTrue(
            app.textFields["trackday.header.car"].waitForExistence(timeout: Self.timeout),
            "Show the Day did not show a day")

        menu("Help", "Take the Tour")
        let step = app.staticTexts["tour.step"]
        XCTAssertTrue(step.waitForExistence(timeout: Self.timeout), "No tour in the Logbook")
        expect(step, toRead: "1 of 3")
        XCTAssertTrue(app.staticTexts["Days, circuits and cars"].exists, "Not the Logbook's tour")
        app.buttons["tour.next"].click()
        app.buttons["tour.next"].click()
        expect(step, toRead: "3 of 3")
        app.buttons["tour.next"].click()
        XCTAssertTrue(step.waitForNonExistence(timeout: Self.timeout))

        app.staticTexts["logbook.scope.all"].click()
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "The checklist did not come back")
        app.buttons["logbook.gettingStarted.hide"].click()
        XCTAssertTrue(title.waitForNonExistence(timeout: Self.timeout), "Hide left the checklist")
        XCTAssertTrue(app.staticTexts["No Session Selected"].exists)
        menu("Help", "Show Getting Started")
        XCTAssertTrue(title.waitForExistence(timeout: Self.timeout), "Show Getting Started did not bring it back")
    }
}
