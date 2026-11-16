import XCTest

// ci-shard: 5
/// J80: line a second logger up with the first by what both recorded (#562).
final class DataAlignmentUITests: OnboardStudioUITestCase {
    @MainActor
    func testASecondDataFileIsLinedUpByItsRPM() throws {
        launch()
        testing("Add Fixture Data (RaceChrono)")
        XCTAssertTrue(sidebarInput("racechrono-v3").waitForExistence(timeout: Self.timeout), "First file not listed")
        testing("Add Fixture Data (Noisy CAN)")
        let second = sidebarInput("racechrono-v3-noisy")
        XCTAssertTrue(second.waitForExistence(timeout: Self.timeout), "Second file not listed")
        second.click()

        let lineUp = app.menuButtons["sync.lineUp"]
        XCTAssertTrue(lineUp.waitForExistence(timeout: Self.timeout), "No Line Up with… for the second file")
        reveal(lineUp)
        lineUp.click()
        let byRPM = lineUp.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'By RPM'")).firstMatch
        XCTAssertTrue(byRPM.waitForExistence(timeout: Self.timeout), "RPM is not offered")
        byRPM.click()
        expectStatus(containing: "Lined up by rpm")
        XCTAssertTrue(
            app.menuBarItems["Edit"].menus.menuItems["Undo Line Up Data File"].exists, "Not a step of Undo")
    }
}
