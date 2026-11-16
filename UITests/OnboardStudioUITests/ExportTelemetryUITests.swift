import XCTest

// ci-shard: 4
/// J79: hand a session's telemetry to another app (#563). Export Telemetry… writes the session, or
/// one lap of it, as CSV, GPX, KML or VBO.
final class ExportTelemetryUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheBestLapIsWrittenAsGPX() throws {
        launch(logbook: true)
        XCTAssertTrue(app.windows["Logbook"].waitForExistence(timeout: Self.timeout), "No Logbook at launch")
        testing("Add Fixture Session at a Circuit")
        XCTAssertTrue(
            app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3), "No import report")
        app.buttons["trackday.done"].click()
        let table = app.descendants(matching: .any).matching(identifier: "logbook.table").firstMatch
        let rowTypes = NSPredicate(
            format: "elementType == %d OR elementType == %d", XCUIElement.ElementType.tableRow.rawValue,
            XCUIElement.ElementType.outlineRow.rawValue)
        let rows = table.descendants(matching: .any).matching(rowTypes)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: Self.timeout), "No session listed")
        rows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)).click()

        let export = app.buttons["logbook.exportTelemetry"]
        XCTAssertTrue(export.waitForExistence(timeout: Self.timeout), "No Export Telemetry… on the session")
        reveal(export)
        export.click()
        let gpx = app.radioButtons["GPX — the path, for maps and fitness apps"]
        XCTAssertTrue(gpx.waitForExistence(timeout: Self.timeout), "No Export Telemetry sheet")
        gpx.click()
        let lap = app.popUpButtons["exportTelemetry.lap"]
        XCTAssertTrue(text(of: lap).contains("(best)"), "The best lap is not chosen to begin with: \(text(of: lap))")
        app.buttons["exportTelemetry.export"].click()

        let message = app.staticTexts["logbook.message"]
        XCTAssertTrue(message.waitForExistence(timeout: Self.timeout), "Nothing says it was exported")
        XCTAssertTrue(text(of: message).contains(".gpx"), text(of: message))
        let written = try FileManager.default.contentsOfDirectory(atPath: Self.exportDirectory.path)
            .filter { $0.hasSuffix(".gpx") }
        XCTAssertFalse(written.isEmpty, "No GPX in the export folder")
    }
}
