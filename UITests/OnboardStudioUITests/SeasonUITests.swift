import XCTest

// ci-shard: 3
/// J46: a season on one page — the numbers, the bests, the chart — and out the door as a card (#355).
final class SeasonUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheSeasonPageSumsTheYearAndExportsACard() throws {
        launch()
        testing("Add Fixture Second Visit")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout))
        expectStatus(containing: "in the logbook")
        let folder = Self.exportDirectory
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])

        menu("Window", "Logbook")
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        XCTAssertTrue(table.waitForExistence(timeout: Self.timeout), "No Logbook window")
        let season = app.radioButtons["Season"].exists ? app.radioButtons["Season"] : app.buttons["Season"]
        XCTAssertTrue(season.waitForExistence(timeout: Self.timeout))
        season.click()
        let summary = app.staticTexts["logbook.season.summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: Self.timeout), "No season page")
        let text = summary.value as? String ?? ""
        XCTAssertTrue(text.contains("2 sessions"), text)
        app.buttons["logbook.season.card"].click()
        let wrote = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).subtracting(before)
                    .contains { $0.hasSuffix("card.png") }
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [wrote], timeout: Self.timeout), .completed, "No card written")
        for name in Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).subtracting(before) {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
    }
}
