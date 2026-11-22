import XCTest

// ci-shard: 6
/// J81: a session's weather filled in from where and when it was driven (#560). Under UI tests the
/// app answers the lookup itself — sunny, dry, 21.5 °C — and nothing is sent.
final class WeatherUITests: OnboardStudioUITestCase {
    /// The fixture track day, in the Logbook, its first session selected; its weather pop-up.
    @MainActor
    private func firstSessionsWeather() -> XCUIElement {
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No sessions listed")
        rows.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()
        let weather = app.popUpButtons["logbook.weather"]
        XCTAssertTrue(weather.waitForExistence(timeout: Self.timeout), "No conditions editor")
        return weather
    }

    @MainActor
    private func expect(_ element: XCUIElement, toRead words: String, _ message: String) {
        let reads = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", words), object: element)
        XCTAssertEqual(
            XCTWaiter().wait(for: [reads], timeout: Self.timeout * 2), .completed,
            "\(message): \(element.value as? String ?? "")")
    }

    /// A session added to the logbook has its weather, surface and air filled in, and says where
    /// they came from.
    @MainActor
    func testANewSessionsWeatherIsLookedUp() throws {
        // Every session counts as new: added after the lookup began.
        launch(extraArguments: ["-lookUpWeather", "YES", "-weatherSince", "1"])
        let weather = firstSessionsWeather()
        expect(weather, toRead: "Sunny", "The weather was not looked up")
        expect(app.popUpButtons["logbook.track"], toRead: "Dry", "The surface was not looked up")
        expect(app.textFields["logbook.temperature"], toRead: "21.5", "The air was not looked up")
        let credit = app.staticTexts["logbook.weatherLookedUp"]
        XCTAssertTrue(credit.waitForExistence(timeout: Self.timeout), "Nothing says the weather was looked up")
    }

    /// The sessions from before are offered once, filled in as one step of Undo.
    @MainActor
    func testEarlierSessionsAreOfferedOnceAndUndoneAsOne() throws {
        // Every session counts as from before the lookup began.
        launch(extraArguments: ["-weatherSince", "4102444800", "-weatherOfferAnswered", "NO"])
        let weather = firstSessionsWeather()
        XCTAssertTrue((weather.value as? String ?? "").contains("Not noted"), "Looked up without being asked")
        let fill = app.buttons["logbook.weatherOffer.fill"]
        XCTAssertTrue(fill.waitForExistence(timeout: Self.timeout), "No offer for the sessions from before")
        fill.click()
        expect(weather, toRead: "Sunny", "Fill In Weather did not fill it in")
        XCTAssertFalse(fill.exists, "The offer came back after it was answered")
        menu("Edit", "Undo Fill In Weather")
        expect(weather, toRead: "Not noted", "One Undo did not take the weather back off")
    }
}
