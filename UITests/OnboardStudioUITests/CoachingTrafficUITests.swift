import XCTest

// ci-shard: 4
/// J67: leave traffic out of the coaching (#571). A corner where another car held the driver up is
/// marked from the walkthrough or the corner's detail; the coaching stops calling it an
/// opportunity, says how much of the lap's loss it was, and the mark is one undo step.
final class CoachingTrafficUITests: OnboardStudioUITestCase {
    @MainActor
    func testACornerHeldUpByTrafficIsLeftOutOfTheCoaching() throws {
        launch()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")
        menu("Project", "Coaching…")

        // The slow lap, in the walkthrough the window opens on.
        let change = app.buttons["coaching.walkthrough.change"]
        XCTAssertTrue(change.waitForExistence(timeout: Self.timeout * 2), "The window did not open on the walkthrough")
        change.click()
        let lapPicker = app.popUpButtons["coaching.lap"]
        XCTAssertTrue(lapPicker.waitForExistence(timeout: Self.timeout), "No lap to choose under Change…")
        choosePopUpItem("Lap 2 — 0:44.60", in: lapPicker)
        app.typeKey(.escape, modifierFlags: [])
        let headline = app.staticTexts["coaching.walkthrough.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: Self.timeout * 2), "No sentence for the lap")
        expect(headline, toContain: "Lap 2")
        XCTAssertFalse(app.staticTexts["coaching.walkthrough.leftOut"].exists, "A corner left out with no mark")

        // Its first corner was traffic: leave it out from the corner's own step.
        app.buttons["coaching.walkthrough.next"].click()
        let leaveOut = app.menuButtons["coaching.walkthrough.leaveOut"]
        XCTAssertTrue(leaveOut.waitForExistence(timeout: Self.timeout), "No Leave This Corner Out on a corner")
        leaveOut.click()
        let traffic = leaveOut.menus.menuItems["Held Up by Traffic"]
        XCTAssertTrue(traffic.waitForExistence(timeout: Self.timeout), "No Held Up by Traffic")
        traffic.click()

        // The reading starts again without it, and says what it left out and what it cost.
        let leftOut = app.staticTexts["coaching.walkthrough.leftOut"]
        XCTAssertTrue(
            leftOut.waitForExistence(timeout: Self.timeout * 2), "The marked corner is not said to be left out")
        expect(headline, toContain: "of it held up by traffic")
        expect(headline, toContain: "Lap 2")

        // One undo step, named for what it did.
        menu("Edit", "Undo Mark Traffic")
        XCTAssertTrue(leftOut.waitForNonExistence(timeout: Self.timeout * 2), "Undo left the corner out")
        menu("Edit", "Redo Mark Traffic")
        XCTAssertTrue(leftOut.waitForExistence(timeout: Self.timeout * 2), "Redo did not leave it out again")

        // In All Corners the table says "traffic", and the corner's detail can change the mark.
        showAllCorners()
        let showMe = app.buttons["coaching.showMe.1"]
        XCTAssertTrue(showMe.waitForExistence(timeout: Self.timeout * 2), "No opportunity left for the slow lap")
        XCTAssertFalse(app.buttons["coaching.showMe.2"].exists, "The marked corner is still an opportunity")
        let allHeadline = app.staticTexts["coaching.headline"]
        expect(allHeadline, toContain: "of it held up by traffic")
        let marked = app.staticTexts.matching(NSPredicate(format: "value == 'traffic'")).firstMatch
        XCTAssertTrue(marked.waitForExistence(timeout: Self.timeout), "The table does not say the corner was traffic")
        marked.click()
        let mark = app.popUpButtons["coaching.trafficMark"]
        XCTAssertTrue(mark.waitForExistence(timeout: Self.timeout), "No mark in the corner's detail")
        XCTAssertTrue(
            app.staticTexts["coaching.trafficNote"].waitForExistence(timeout: Self.timeout),
            "The detail does not say why the corner is left out")
        choosePopUpItem("Driven Freely", in: mark)
        XCTAssertTrue(
            app.buttons["coaching.showMe.2"].waitForExistence(timeout: Self.timeout * 2),
            "Clearing the mark did not bring the corner back")
        menu("Edit", "Undo Clear Traffic Mark")
        XCTAssertTrue(
            app.buttons["coaching.showMe.2"].waitForNonExistence(timeout: Self.timeout * 2),
            "Undo did not put the mark back")
    }
}
