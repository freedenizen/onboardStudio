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
}
