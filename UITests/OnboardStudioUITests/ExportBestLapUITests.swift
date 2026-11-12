import XCTest

// ci-shard: 3
/// J56: export your best lap (#467). The range is the first thing in the Export Video sheet; a lap
/// range starts on the best lap, every lap listed with its time, and never runs backwards; and
/// the file is named after the project, not "Onboard Studio Export".
final class ExportBestLapUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheBestLapIsOfferedFirstAndExportedUnderTheProjectsName() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        app.buttons["toolbar.export"].click()

        // What to export comes before how.
        let range = app.popUpButtons["export.range"]
        XCTAssertTrue(range.waitForExistence(timeout: Self.timeout), "No range in the sheet")
        let preset = app.popUpButtons["export.preset"]
        XCTAssertTrue(preset.exists, "No preset in the sheet")
        XCTAssertLessThan(range.frame.minY, preset.frame.minY, "The range is not the first thing in the sheet")

        // Laps: from the best lap to the best lap, each lap with its time.
        choosePopUpItem("Laps", in: range)
        let from = app.popUpButtons["export.firstLap"]
        let to = app.popUpButtons["export.lastLap"]
        XCTAssertTrue(from.waitForExistence(timeout: Self.timeout), "No first lap")
        let best = from.value as? String ?? ""
        XCTAssertTrue(best.hasSuffix("(best)"), "A lap range does not start on the best lap: “\(best)”")
        XCTAssertEqual(to.value as? String, best, "The last lap is not the best lap too")
        let laps = titles(of: from)
        XCTAssertGreaterThan(laps.count, 1, "The fixture should have more than one lap: \(laps)")
        XCTAssertTrue(laps.allSatisfy { $0.hasPrefix("Lap ") && $0.contains(" · ") }, "A lap without its time: \(laps)")

        // Moving either end past the other brings the other with it.
        let last = try XCTUnwrap(laps.last)
        let first = try XCTUnwrap(laps.first)
        choosePopUpItem(last, in: from)
        XCTAssertEqual(to.value as? String, last, "The last lap stayed before the first")
        choosePopUpItem(first, in: to)
        XCTAssertEqual(from.value as? String, first, "The first lap stayed after the last")

        // Back to the best lap, and out under the project's own name.
        choosePopUpItem(best, in: to)
        choosePopUpItem(best, in: from)
        let project = projectWindows.firstMatch.title
        XCTAssertFalse(project.isEmpty, "The project window has no title")
        let file = Self.exportDirectory.appending(path: "\(project).mp4")
        try? FileManager.default.removeItem(at: file)
        app.buttons["export.start"].click()
        XCTAssertTrue(app.buttons["export.reveal"].waitForExistence(timeout: 90), "The export did not finish")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "No \(file.lastPathComponent)")
        try? FileManager.default.removeItem(at: file)
    }

    /// The titles of a pop-up's items, read with its menu open, which Escape then closes.
    @MainActor
    private func titles(of popUp: XCUIElement) -> [String] {
        reveal(popUp)
        popUp.click()
        let items = popUp.menus.menuItems
        XCTAssertTrue(items.firstMatch.waitForExistence(timeout: Self.timeout), "The pop-up did not open")
        let titles = items.allElementsBoundByIndex.map(\.title).filter { !$0.isEmpty }
        app.typeKey(.escape, modifierFlags: [])
        return titles
    }
}
