import XCTest

// ci-shard: 2
/// J63: prepare to go back to a circuit (#460). Choosing it in the Logbook's sidebar shows what to
/// know before going: the personal best, the last visit and a plan to write and change right
/// there; New Track Day Here… begins the next day at it, which shows the same card.
final class PrepareForACircuitUITests: OnboardStudioUITestCase {
    private var sidebar: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "logbook.sidebar").firstMatch
    }
    private var cardTitle: XCUIElement { app.staticTexts["circuit.card.title"] }
    private var experiment: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "coaching.plan.experiment.1").firstMatch
    }

    @MainActor
    func testAPlanIsWrittenForTheCircuitAndGreetsTheNextDay() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        app.buttons["trackday.done"].click()

        let sonoma = sidebar.staticTexts["Sonoma Raceway"]
        XCTAssertTrue(sonoma.waitForExistence(timeout: Self.timeout), "No Sonoma Raceway in the sidebar")
        sonoma.click()
        XCTAssertTrue(cardTitle.waitForExistence(timeout: Self.timeout), "No card for the circuit")
        expect(cardTitle, toRead: "Sonoma Raceway")
        expect(app.staticTexts["circuit.card.subtitle"], toContain: "visits · personal best")
        XCTAssertTrue(app.staticTexts["circuit.card.lastVisit"].exists, "No word of the last visit")

        // A plan begun on the card, written in, and the writing taken back by Undo.
        app.buttons["circuit.plan.start"].click()
        XCTAssertTrue(experiment.waitForExistence(timeout: Self.timeout), "Start a Plan gave no line to write in")
        experiment.click()
        experiment.typeText("Brake at the 2 board into turn 2\n")
        expect(experiment, toRead: "Brake at the 2 board into turn 2")
        app.staticTexts["logbook.scope.all"].click()
        sonoma.click()
        XCTAssertTrue(experiment.waitForExistence(timeout: Self.timeout))
        expect(experiment, toRead: "Brake at the 2 board into turn 2")
        menu("Edit", "Undo Change Experiment")
        expect(experiment, toRead: "")
        menu("Edit", "Redo Change Experiment")
        expect(experiment, toRead: "Brake at the 2 board into turn 2")

        // The next day there begins at the circuit, and shows the plan until its first session.
        app.buttons["circuit.card.newDay"].click()
        XCTAssertTrue(
            app.staticTexts["trackday.new.circuit.chosen"].waitForExistence(timeout: Self.timeout),
            "New Track Day Here… did not begin at the circuit")
        app.buttons["trackday.new.create"].click()
        XCTAssertTrue(app.staticTexts["trackday.header.title"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(cardTitle.waitForExistence(timeout: Self.timeout), "The new day does not show the card")
        XCTAssertFalse(app.buttons["circuit.card.newDay"].exists, "A day offers to begin another day")
        expect(experiment, toRead: "Brake at the 2 board into turn 2")

        // The plan's last line removed takes the plan away.
        app.buttons["coaching.plan.remove.1"].click()
        XCTAssertTrue(experiment.waitForNonExistence(timeout: Self.timeout), "The line was not removed")
    }

    /// A plan saved in the Coaching window for a session at the circuit is on the card at once,
    /// not after a relaunch (#543), and is a step of the Logbook's Undo like the card's own edits.
    /// The coaching fixture, on a day at Sonoma, has a slow lap with corners to plan from; the
    /// Sonoma fixtures' laps are too short to have any.
    @MainActor
    func testAPlanMadeInCoachingIsOnTheCardAtOnce() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        app.buttons["logbook.newTrackDay"].click()
        let search = app.textFields["trackday.new.circuit"]
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout), "No New Track Day sheet")
        search.click()
        search.typeText("Sonoma")
        let match = app.descendants(matching: .any).matching(identifier: "trackday.new.match.Sonoma Raceway").firstMatch
        XCTAssertTrue(match.waitForExistence(timeout: Self.timeout), "The catalogue did not offer Sonoma")
        match.click()
        app.buttons["trackday.new.create"].click()
        XCTAssertTrue(app.staticTexts["trackday.header.title"].waitForExistence(timeout: Self.timeout))
        testing("Add Fixture Sessions to Selected Day")
        _ = finishAddingToDay(.thisDay)

        // The card has no plan yet.
        let sonoma = sidebar.staticTexts["Sonoma Raceway"]
        XCTAssertTrue(sonoma.waitForExistence(timeout: Self.timeout), "No Sonoma Raceway in the sidebar")
        sonoma.click()
        let start = app.buttons["circuit.plan.start"]
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout), "The card does not offer to start a plan")

        // Coaching on the coaching session, its slow lap, to the plan, saved for the circuit.
        let find = app.searchFields.firstMatch
        find.click()
        find.typeText("coaching-laps")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let row = table.descendants(matching: .any).matching(
            NSPredicate(
                format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
                XCUIElement.ElementType.outlineRow.rawValue)
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No coaching session at Sonoma")
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        app.buttons["logbook.coach"].click()
        let step = app.staticTexts["coaching.walkthrough.step"]
        XCTAssertTrue(step.waitForExistence(timeout: Self.timeout * 2), "Coaching did not open on the walkthrough")
        app.buttons["coaching.walkthrough.change"].click()
        let lapPicker = app.popUpButtons["coaching.lap"]
        XCTAssertTrue(lapPicker.waitForExistence(timeout: Self.timeout), "No lap to choose under Change…")
        choosePopUpItem("Lap 2 — 0:44.60", in: lapPicker)
        app.typeKey(.escape, modifierFlags: [])
        let next = app.buttons["coaching.walkthrough.next"]
        for _ in 0..<6 where next.exists { next.click() }
        expect(step, toRead: "Your Plan")
        let save = app.buttons["coaching.walkthrough.savePlan"]
        XCTAssertTrue(save.isEnabled, "Nothing to save for Sonoma")
        save.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["coaching.walkthrough.saved"].waitForExistence(timeout: Self.timeout),
            "The plan was not saved")

        // Back in the Logbook, the card has it, and Undo takes it back as one step.
        menu("Window", "Logbook")
        XCTAssertTrue(experiment.waitForExistence(timeout: Self.timeout), "The card does not show the plan")
        XCTAssertFalse(start.exists, "The card still offers to start a plan")
        menu("Edit", "Undo Make Plan")
        XCTAssertTrue(start.waitForExistence(timeout: Self.timeout), "Undo did not take the plan away")
        XCTAssertFalse(experiment.exists, "The plan is still on the card after Undo")
        menu("Edit", "Redo Make Plan")
        XCTAssertTrue(experiment.waitForExistence(timeout: Self.timeout), "Redo did not bring the plan back")
    }
}
