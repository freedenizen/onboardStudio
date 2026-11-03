import XCTest

// ci-shard: 2
/// J35: plan the next session — the Coaching window writes three experiments from the
/// opportunities, the driver edits them, and each step is one undo (#330).
final class CoachingPlanUITests: OnboardStudioUITestCase {
    @MainActor
    func testAPlanIsMadeEditedAndUndone() throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")

        menu("Project", "Coaching…")
        let lapPicker = app.popUpButtons["coaching.lap"]
        XCTAssertTrue(lapPicker.waitForExistence(timeout: Self.timeout * 2), "The Coaching window did not open")
        choosePopUpItem("Lap 2 — 0:44.60", in: lapPicker)
        let makePlan = app.buttons["coaching.makePlan"]
        XCTAssertTrue(makePlan.waitForExistence(timeout: Self.timeout * 2), "No Make a Plan button")
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: makePlan)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: Self.timeout * 2), .completed, "Never enabled")
        makePlan.click()

        // The slow lap loses time in both corners: two experiments, no third.
        let first = app.textFields["coaching.plan.experiment.1"]
        XCTAssertTrue(first.waitForExistence(timeout: Self.timeout), "No plan was made")
        XCTAssertTrue(app.textFields["coaching.plan.experiment.2"].exists)
        XCTAssertFalse(app.textFields["coaching.plan.experiment.3"].exists)
        let suggested = first.value as? String ?? ""
        XCTAssertFalse(suggested.isEmpty, "The experiment should be worded from the opportunity")

        // Editing commits on Return and is one undo step.
        first.click()
        first.typeKey("a", modifierFlags: .command)
        first.typeText("Brake at the 2 board.\n")
        XCTAssertEqual(first.value as? String, "Brake at the 2 board.")
        menu("Edit", "Undo Edit Plan")
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", suggested), object: first)
        XCTAssertEqual(XCTWaiter().wait(for: [restored], timeout: Self.timeout), .completed, "Undo did not restore")

        // Removing one and undoing it.
        app.buttons["coaching.plan.remove.2"].click()
        XCTAssertTrue(app.textFields["coaching.plan.experiment.2"].waitForNonExistence(timeout: Self.timeout))
        menu("Edit", "Undo Remove Experiment")
        XCTAssertTrue(app.textFields["coaching.plan.experiment.2"].waitForExistence(timeout: Self.timeout))

        // And the plan itself.
        menu("Edit", "Undo Make Plan")
        XCTAssertTrue(makePlan.waitForExistence(timeout: Self.timeout), "Undo Make Plan did not remove the plan")
    }
}
