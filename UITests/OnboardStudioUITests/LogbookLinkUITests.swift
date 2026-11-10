import XCTest

// ci-shard: 3
/// J40: a data file added to a project is in the logbook too, without being asked (#349).
final class LogbookLinkUITests: OnboardStudioUITestCase {
    @MainActor
    func testADataFileAddedToAProjectIsEnteredInTheLogbook() throws {
        launch()
        addFixtureData()
        expectStatus(containing: "in the logbook")

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "The logbook is still empty")
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "Not one session")
        // The same file added again is the same entry, not a second one.
        app.typeKey("w", modifierFlags: .command)
        testing("Add Fixture Data (RaceRender)")
        expectStatus(containing: "in the logbook")
        menu("Window", "Logbook")
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout))
        let still = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == 1"), object: rows)
        XCTAssertEqual(XCTWaiter().wait(for: [still], timeout: Self.timeout), .completed, "Entered twice")
    }
}
