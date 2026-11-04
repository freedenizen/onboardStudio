import XCTest

// ci-shard: 2
/// J45: two cars at one circuit set against each other — which is quicker and where (#354).
final class CarVersusCarUITests: OnboardStudioUITestCase {
    @MainActor
    func testTwoCarsAtOneCircuitAreCompared() throws {
        launch()
        testing("Add Fixture Second Visit in a GR86")
        expectStatus(containing: "in the GR86")
        testing("Set Project Car Miata")
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout))
        expectStatus(containing: "in the logbook")

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        let trends = app.radioButtons["Trends"].exists ? app.radioButtons["Trends"] : app.buttons["Trends"]
        XCTAssertTrue(trends.waitForExistence(timeout: Self.timeout))
        trends.click()
        let headline = app.staticTexts["logbook.cars.headline"]
        XCTAssertTrue(headline.waitForExistence(timeout: Self.timeout * 3), "No car-against-car reading")
        let text = headline.value as? String ?? ""
        XCTAssertTrue(text.contains("Miata") && text.contains("GR86"), text)
        let sentence = app.staticTexts["logbook.cars.sentence.1"]
        XCTAssertTrue(sentence.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue((sentence.value as? String ?? "").hasPrefix("Turn 1"), sentence.value as? String ?? "")
    }
}
