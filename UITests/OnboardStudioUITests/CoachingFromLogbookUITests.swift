import XCTest

// ci-shard: 3
/// J49: a logbook session is coached with no project open — the window reads its file, offers
/// the references, keeps the choices on the entry, and exports the sheet (#396).
final class CoachingFromLogbookUITests: OnboardStudioUITestCase {
    @MainActor
    func testASessionIsCoachedWithNoProjectOpen() throws {
        selectTheCoachingSession()
        XCTAssertFalse(app.windows["Untitled"].exists, "Still no project")
        pressCoach()

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

    /// #462: with the session's project open, Coach… reads that project — the plan is there, and
    /// nothing offers a second project.
    @MainActor
    func testCoachFindsTheProjectOpenOnTheSession() throws {
        selectTheCoachingSession()
        newProjectFromTheSession()
        menu("Window", "Logbook")
        pressCoach()

        XCTAssertTrue(app.staticTexts["coaching.headline"].waitForExistence(timeout: Self.timeout * 2), "No reading")
        XCTAssertTrue(
            app.buttons["coaching.makePlan"].waitForExistence(timeout: Self.timeout),
            "No plan: Coach… did not find the project open on the session")
        XCTAssertFalse(app.buttons["coaching.makeProject"].exists, "A project is offered beside the one open")
        XCTAssertFalse(app.buttons["coaching.useOpenProject"].exists)
        XCTAssertFalse(app.windows["Untitled 2"].exists, "A second project")
    }

    /// #462: a project made after the Coaching window opened on the session is followed, not
    /// made again — the button says so.
    @MainActor
    func testMakeAProjectFollowsTheProjectAlreadyOpen() throws {
        selectTheCoachingSession()
        pressCoach()
        XCTAssertTrue(app.buttons["coaching.makeProject"].waitForExistence(timeout: Self.timeout * 2))

        menu("Window", "Logbook")
        newProjectFromTheSession()
        menu("Window", "Coaching")
        let use = app.buttons["coaching.useOpenProject"]
        XCTAssertTrue(use.waitForExistence(timeout: Self.timeout), "Still offers to make a project")
        XCTAssertFalse(app.buttons["coaching.makeProject"].exists)
        use.click()

        XCTAssertTrue(app.buttons["coaching.makePlan"].waitForExistence(timeout: Self.timeout * 2), "No plan")
        XCTAssertFalse(app.windows["Untitled 2"].exists, "A second project")
    }

    /// The Logbook at launch, a day added, and the coaching fixture's session selected.
    @MainActor
    private func selectTheCoachingSession() {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout), "No Add Track Day sheet")
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()

        // Found by its file name.
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
    }

    @MainActor
    private func pressCoach() {
        let coach = app.buttons["logbook.coach"]
        XCTAssertTrue(coach.waitForExistence(timeout: Self.timeout), "No Coach… in the detail")
        coach.click()
    }

    /// New Project in the session's detail, waited for until its data file is in.
    @MainActor
    private func newProjectFromTheSession() {
        XCTAssertTrue(sessionNewProject.waitForExistence(timeout: Self.timeout), "No New Project in the detail")
        pressSplitButton(sessionNewProject)
        XCTAssertTrue(app.windows["Untitled"].waitForExistence(timeout: Self.timeout), "No new project")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout * 2), "No data input")
    }
}
