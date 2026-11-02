import XCTest

// ci-shard: 1
/// J41: take the logbook with you — a folder of sessions, a CSV, a Markdown summary (#350).
final class LogbookTransferUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheLogbookExportsAsAFolderAndAsCSV() throws {
        launch()
        testing("Add Fixture Track Day")
        let done = app.buttons["trackday.done"]
        XCTAssertTrue(done.waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["trackday.summary"].waitForExistence(timeout: Self.timeout * 3))
        done.click()
        let folder = Self.exportDirectory
        let csv = folder.appending(path: "Logbook.csv")
        let exported = folder.appending(path: "Logbook")
        try? FileManager.default.removeItem(at: csv)
        try? FileManager.default.removeItem(at: exported)
        defer {
            try? FileManager.default.removeItem(at: csv)
            try? FileManager.default.removeItem(at: exported)
        }

        menu("Window", "Logbook")
        let transfer = app.menuButtons["logbook.transfer"]
        XCTAssertTrue(transfer.waitForExistence(timeout: Self.timeout), "No Export or Import menu")
        transfer.click()
        let asCSV = transfer.menus.menuItems["Export Sessions as CSV…"]
        XCTAssertTrue(asCSV.waitForExistence(timeout: Self.timeout))
        asCSV.click()
        let wroteCSV = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in FileManager.default.fileExists(atPath: csv.path) }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [wroteCSV], timeout: Self.timeout), .completed, "No CSV")
        let text = try String(contentsOf: csv, encoding: .utf8)
        XCTAssertTrue(text.hasPrefix("date,circuit,car,driver,laps,best"), text)
        XCTAssertGreaterThan(text.split(separator: "\n").count, 2, "a line per session")
        XCTAssertTrue(app.staticTexts["logbook.message"].waitForExistence(timeout: Self.timeout))

        transfer.click()
        let asFolder = transfer.menus.menuItems["Export Logbook…"]
        XCTAssertTrue(asFolder.waitForExistence(timeout: Self.timeout))
        asFolder.click()
        let wroteFolder = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in
                ((try? FileManager.default.contentsOfDirectory(atPath: exported.path)) ?? [])
                    .contains { $0.hasSuffix(".onboardsession") }
            }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [wroteFolder], timeout: Self.timeout), .completed, "No session files")
    }
}
