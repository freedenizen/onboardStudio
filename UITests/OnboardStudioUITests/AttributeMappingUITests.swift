import XCTest

/// #111 and #89: telling the app where an attribute comes from and what it is read and shown in,
/// from the surface the user actually meets it on.
final class AttributeMappingUITests: OnboardStudioUITestCase {
    @MainActor
    func testMapsAnAttributeToAColumnAndUnits() throws {
        launch()
        addFixtureData()
        sidebarInput("racerender-basic").click()

        // Speed is in the file, so its row shows without asking for every attribute.
        let speed = app.staticTexts["attribute.speed"]
        XCTAssertTrue(speed.waitForExistence(timeout: Self.timeout), "No Speed row in the attribute table")

        // Reading the column as mph and showing it in km/h are two separate choices; making the
        // first must not make the second.
        let reads = app.popUpButtons["attribute.speed.sourceUnit"]
        reveal(reads)
        choosePopUpItem("mph", in: reads)
        XCTAssertTrue(
            summary(of: "attribute.speed").contains("mph"), "The row does not report the unit it now reads")

        let shows = app.popUpButtons["attribute.speed.displayUnit"]
        reveal(shows)
        choosePopUpItem("km/h", in: shows)
        XCTAssertTrue(
            summary(of: "attribute.speed").contains("mph → km/h"),
            "The row does not report reading one unit and showing another")

        // Undo puts the mapping back, because it is a project edit like any other.
        app.typeKey("z", modifierFlags: .command)
        XCTAssertFalse(
            summary(of: "attribute.speed").contains("→"), "Undo left the display unit pinned")
    }

    /// An attribute the file does not supply is still mappable — that is the whole point of asking
    /// the question attribute-first — but it stays out of the way until asked for.
    @MainActor
    func testHidesAttributesTheFileDoesNotSupplyUntilAsked() throws {
        launch()
        addFixtureData()
        sidebarInput("racerender-basic").click()

        // Queried by identifier alone: a SwiftUI Toggle is a checkbox in one context and a switch
        // in another, and which one it is here is not what this test is about.
        let showAll = app.descendants(matching: .any).matching(identifier: "attributes.showAll").firstMatch
        XCTAssertTrue(showAll.waitForExistence(timeout: Self.timeout), "No way to see every attribute")
        let brake = app.staticTexts["attribute.brake"]
        XCTAssertFalse(brake.exists, "An attribute the file does not supply is shown unasked")

        reveal(showAll)
        showAll.click()
        XCTAssertTrue(brake.waitForExistence(timeout: Self.timeout), "Showing every attribute left Brake out")
    }

    /// The caption on the right of a row, which states the mapping in force.
    @MainActor
    private func summary(of identifier: String) -> String {
        let row = app.staticTexts[identifier]
        XCTAssertTrue(row.waitForExistence(timeout: Self.timeout), "No row “\(identifier)”")
        return (row.value as? String) ?? row.label
    }
}
