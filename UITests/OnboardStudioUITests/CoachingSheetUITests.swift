import PDFKit
import XCTest

// ci-shard: 2
/// J36: the debrief on one page — File ▸ Export Coaching Sheet writes the Coaching window's
/// reading as a PDF and as Markdown (#331).
final class CoachingSheetUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheSheetExportsAsPDFAndMarkdown() throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")
        let folder = Self.exportDirectory

        menu("Project", "Coaching…")
        let lapPicker = app.popUpButtons["coaching.lap"]
        XCTAssertTrue(lapPicker.waitForExistence(timeout: Self.timeout * 2), "The Coaching window did not open")
        choosePopUpItem("Lap 2 — 0:44.60", in: lapPicker)
        XCTAssertTrue(app.buttons["coaching.showMe.1"].waitForExistence(timeout: Self.timeout * 2), "No reading")

        // The items are in the File menu while the Coaching window has a reading. The file is
        // named for the track (none in the fixture) and the lap; look for it by its suffix.
        func sheets(_ suffix: String) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
                .filter { $0.hasSuffix("coaching sheet.\(suffix)") }
        }
        for name in sheets("pdf") + sheets("md") {
            try? FileManager.default.removeItem(at: folder.appending(path: name))
        }
        defer {
            for name in sheets("pdf") + sheets("md") {
                try? FileManager.default.removeItem(at: folder.appending(path: name))
            }
        }

        menu("File", "Export Coaching Sheet as PDF…")
        let wrote = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !sheets("pdf").isEmpty }, object: nil)
        let status = app.staticTexts["status.message"]
        XCTAssertEqual(
            XCTWaiter().wait(for: [wrote], timeout: Self.timeout), .completed,
            "No PDF in \(folder.path); status: \(status.value ?? "none")")
        let pdfName = try XCTUnwrap(sheets("pdf").first)
        XCTAssertTrue(pdfName.hasSuffix("Lap 2 coaching sheet.pdf"), pdfName)
        let document = try XCTUnwrap(PDFDocument(url: folder.appending(path: pdfName)), "The PDF does not open")
        XCTAssertEqual(document.pageCount, 1, "One page")
        let text = document.string ?? ""
        XCTAssertTrue(text.contains("Lap 2"), text)
        XCTAssertTrue(text.contains("Turn"), text)

        menu("File", "Export Coaching Sheet as Markdown…")
        let wroteMarkdown = XCTNSPredicateExpectation(
            predicate: NSPredicate { _, _ in !sheets("md").isEmpty }, object: nil)
        XCTAssertEqual(XCTWaiter().wait(for: [wroteMarkdown], timeout: Self.timeout), .completed, "No Markdown")
        let markdownName = try XCTUnwrap(sheets("md").first)
        let body = try String(contentsOf: folder.appending(path: markdownName), encoding: .utf8)
        XCTAssertTrue(body.contains("## Every corner"), body)
        XCTAssertTrue(body.contains("| 1 | "), body)
    }
}
