import XCTest

// ci-shard: 5
/// J66: an autocross's runs in the Logbook, on a course of their own (#552).
final class CoursesUITests: OnboardStudioUITestCase {
    @MainActor
    func testRunsAreKeptOnACourseThatCanBeRenamed() throws {
        launch()
        testing("Add Fixture Autocross to Logbook")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout * 3), "No Add Track Day sheet")
        done.click()

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        // Its runs, the one that never finished a DNF, and the course they were on.
        let detail = app.descendants(matching: .any).matching(identifier: "logbook.detail").firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: Self.timeout), "No detail for the session")
        XCTAssertTrue(detail.staticTexts["Run 1"].waitForExistence(timeout: Self.timeout), "No runs listed")
        XCTAssertTrue(detail.staticTexts["DNF"].exists, "The unfinished run is not a DNF")
        XCTAssertFalse(detail.staticTexts["Fastest rolling lap"].exists, "A rolling lap offered for runs")
        let course = app.textFields["logbook.detail.course"]
        XCTAssertTrue(course.waitForExistence(timeout: Self.timeout), "No course")
        XCTAssertTrue(text(of: course).hasPrefix("Course of "), "Course named \(text(of: course))")

        // Renamed once for every session on it, and the sidebar follows; Undo takes it back.
        course.click()
        course.typeKey("a", modifierFlags: .command)
        course.typeText("Spring layout\r")
        let renamed = app.staticTexts["Spring layout"]
        XCTAssertTrue(renamed.waitForExistence(timeout: Self.timeout), "The sidebar did not follow the rename")
        menu("Edit", "Undo Rename Course")
        XCTAssertTrue(renamed.waitForNonExistence(timeout: Self.timeout), "Undo did not take the name back")
    }
}
