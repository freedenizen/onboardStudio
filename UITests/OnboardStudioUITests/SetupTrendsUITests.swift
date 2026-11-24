import XCTest

// ci-shard: 4
/// J76: did a change help (#559). Two visits on different tyres: Trends narrows to one set, and
/// Before and After reads one set against the other.
final class SetupTrendsUITests: OnboardStudioUITestCase {
    @MainActor
    func testTrendsSplitTheSessionsByTheirTyres() throws {
        launch()
        testing("Add Fixture Second Visit")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout))
        expectStatus(containing: "in the logbook")

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count >= 2"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "Two sessions not listed")
        // The tyres of each visit, typed on the session.
        for (index, set) in ["Old Set", "New Set"].enumerated() {
            rows.element(boundBy: index).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
            let tyres = app.textFields["logbook.tyres"]
            XCTAssertTrue(tyres.waitForExistence(timeout: Self.timeout), "No conditions editor")
            reveal(tyres)
            tyres.click()
            tyres.typeText("\(set)\n")
            XCTAssertTrue(app.staticTexts[set].waitForExistence(timeout: Self.timeout), "\(set) not kept")
        }

        let trends = app.radioButtons["Trends"].exists ? app.radioButtons["Trends"] : app.buttons["Trends"]
        trends.click()
        // Nothing is compared until it is asked for (#670): the section says to choose, and Tyres
        // is what these two visits differ by.
        let prompt = app.staticTexts["logbook.trends.beforeAfter.choose"]
        reveal(prompt)
        XCTAssertTrue(prompt.waitForExistence(timeout: Self.timeout), "Before and after does not ask what to compare")
        choosePopUpItem("Tyres", in: app.popUpButtons["logbook.trends.beforeAfter.split"])
        let headline = app.staticTexts["logbook.trends.beforeAfter.headline"]
        reveal(headline)
        XCTAssertTrue(headline.waitForExistence(timeout: Self.timeout), "No Before and After")
        XCTAssertTrue(text(of: headline).contains("each session's best averaged"), text(of: headline))
        XCTAssertTrue(text(of: headline).contains("(1 session against 1)"), text(of: headline))
        let shot = XCTAttachment(screenshot: app.windows["Logbook"].screenshot())
        shot.name = "Before and after"
        shot.lifetime = .keepAlways
        add(shot)

        // Narrowed to one set, one visit is not a trend.
        let filter = app.popUpButtons["logbook.trends.filter.tyres"]
        XCTAssertTrue(filter.waitForExistence(timeout: Self.timeout), "No tyre filter")
        choosePopUpItem("New Set", in: filter)
        let summary = app.staticTexts["logbook.trends.summary"]
        let one = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS 'One visit' OR label CONTAINS 'One visit'"), object: summary)
        XCTAssertEqual(XCTWaiter().wait(for: [one], timeout: Self.timeout), .completed, text(of: summary))
        app.buttons["logbook.trends.filter.clear"].click()
        let two = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS '2 sessions' OR label CONTAINS '2 sessions'"),
            object: summary)
        XCTAssertEqual(XCTWaiter().wait(for: [two], timeout: Self.timeout), .completed, text(of: summary))
    }
}
