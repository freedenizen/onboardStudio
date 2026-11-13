import XCTest

// ci-shard: 3
/// J64: set a goal and follow it (#461). A lap time set on a circuit's card says how far there is
/// to go, is drawn on Trends, and can be removed and brought back with Undo; one already met is
/// listed on the Season as reached.
final class GoalsUITests: OnboardStudioUITestCase {
    private var sidebar: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "logbook.sidebar").firstMatch
    }
    private var firstGoal: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "circuit.goal.1").firstMatch
    }

    /// Add Goal… on the card, a lap time typed, Add Goal.
    @MainActor
    private func addLapGoal(_ time: String) {
        app.buttons["circuit.goal.add"].click()
        let field = app.textFields["goal.target"]
        XCTAssertTrue(field.waitForExistence(timeout: Self.timeout), "No goal editor")
        field.click()
        field.typeText(time)
        app.buttons["goal.addButton"].click()
        XCTAssertTrue(field.waitForNonExistence(timeout: Self.timeout), "The editor stayed open")
    }

    @MainActor
    func testALapTimeGoalIsFollowedOnTheCardTrendsAndSeason() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        app.buttons["trackday.done"].click()
        let sonoma = sidebar.staticTexts["Sonoma Raceway"]
        XCTAssertTrue(sonoma.waitForExistence(timeout: Self.timeout), "No Sonoma Raceway in the sidebar")
        sonoma.click()
        XCTAssertTrue(app.buttons["circuit.goal.add"].waitForExistence(timeout: Self.timeout), "No Add Goal…")

        // Quicker than the fixtures' best there: how far is left.
        addLapGoal("0:00.50")
        XCTAssertTrue(firstGoal.waitForExistence(timeout: Self.timeout), "The goal is not on the card")
        expect(firstGoal, toContain: "0:00.50 lap")
        expect(firstGoal, toContain: "to go")

        // Trends draws it, and says so.
        app.typeKey("2", modifierFlags: .command)
        let caption = app.staticTexts["logbook.trends.goal"]
        XCTAssertTrue(caption.waitForExistence(timeout: Self.timeout), "Trends does not show the goal")
        expect(caption, toContain: "0:00.50 lap")
        app.typeKey("1", modifierFlags: .command)

        // Removed, and back with Undo.
        XCTAssertTrue(firstGoal.waitForExistence(timeout: Self.timeout))
        app.buttons["circuit.goal.remove.1"].click()
        XCTAssertTrue(firstGoal.waitForNonExistence(timeout: Self.timeout), "The goal was not removed")
        menu("Edit", "Undo Remove Goal")
        XCTAssertTrue(firstGoal.waitForExistence(timeout: Self.timeout), "Undo did not bring the goal back")

        // Slower than the best there: reached already, and the Season lists it.
        addLapGoal("0:01.00")
        let second = app.descendants(matching: .any).matching(identifier: "circuit.goal.2").firstMatch
        XCTAssertTrue(second.waitForExistence(timeout: Self.timeout))
        expect(second, toContain: "Reached on")
        app.typeKey("3", modifierFlags: .command)
        let reached = app.descendants(matching: .any).matching(identifier: "logbook.season.goals").firstMatch
        XCTAssertTrue(reached.waitForExistence(timeout: Self.timeout), "The Season does not list the goal reached")
    }
}
