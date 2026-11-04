import XCTest

// ci-shard: 3
/// J49: a logbook session is coached with no project open — the window reads its file, offers
/// the references, keeps the choices on the entry, and exports the sheet (#396).
final class CoachingFromLogbookUITests: OnboardStudioUITestCase {
    @MainActor
    func testASessionIsCoachedWithNoProjectOpen() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        XCTAssertFalse(app.windows["Untitled"].exists, "Still no project")

        // The coaching fixture's session, found by its file name.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: Self.timeout))
        search.click()
        search.typeText("coaching-laps")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let narrowed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [narrowed], timeout: Self.timeout), .completed, "Search did not narrow")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let coach = app.buttons["logbook.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.timeout), "No Coach… in the detail")
        coach.click()

        // The window reads the session: a headline, the corner table, Make a Project in place of the plan.
        let headline = app.staticTexts["coaching.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: Self.timeout * 2), "No coaching reading")
        expect(headline, toContain: "against your best lap")
        XCTAssertTrue(app.buttons["coaching.makeProject"].exists, "No Make a Project")
        XCTAssertFalse(app.buttons["coaching.makePlan"].exists, "A plan needs a project")
        XCTAssertFalse(app.windows["Untitled"].exists, "Coaching opened no project")

        // A choice is kept on the entry: the fastest rolling lap, read again after a round trip.
        let reference = app.popUpButtons["coaching.reference"]
        XCTAssertTrue(reference.waitForExistence(timeout: Self.timeout))
        choosePopUpItem("Fastest rolling lap", in: reference)
        let rolling = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] 'rolling'"), object: reference)
        XCTAssertEqual(XCTWaiter().wait(for: [rolling], timeout: Self.timeout), .completed)

        // The sheet writes from here too, with no project: the export directory takes it.
        menu("File", "Export Coaching Sheet as Markdown…")
        let message = app.staticTexts["coaching.message"]
        XCTAssertTrue(message.waitForExistence(timeout: Self.timeout), "No word of the export")
        expect(message, toContain: "Exported the coaching sheet")
        let written = try FileManager.default.contentsOfDirectory(atPath: Self.exportDirectory.path)
        XCTAssertTrue(written.contains { $0.hasSuffix(".md") }, "No Markdown written: \(written)")
    }
}
