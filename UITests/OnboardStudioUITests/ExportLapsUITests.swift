import XCTest

// ci-shard: 2
/// J23: export a session as one file per lap (#150).
final class ExportLapsUITests: OnboardStudioUITestCase {
    @MainActor
    func testEveryLapIsWrittenAsItsOwnFile() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        app.buttons["toolbar.export"].click()
        choose("Every lap, one file each", inPopUpShowing: "Whole project")
        // The sheet says which files it will write before it writes them.
        let files = app.staticTexts["export.lapFiles"]
        XCTAssertTrue(files.waitForExistence(timeout: Self.timeout), "No list of the files to be written")
        let promised = lapNumbers(in: text(of: files))
        XCTAssertFalse(promised.isEmpty, "The fixture should have a complete lap: \(text(of: files))")
        // (Which laps a filter keeps is `LapExportsTests`' job; the fixture's three seconds hold
        // no partial lap to let in.)
        let all = promised

        let folder = Self.exportDirectory
        let expected = all.map { folder.appending(path: "Onboard Studio Export – Lap \($0).mp4") }
        for url in expected { try? FileManager.default.removeItem(at: url) }
        app.buttons["export.start"].click()
        XCTAssertTrue(app.buttons["export.reveal"].waitForExistence(timeout: 90), "The export did not finish")
        for url in expected {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "No \(url.lastPathComponent)")
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// The lap numbers in "Writes 3 files: Lap 1, Lap 2, Lap 3."
    func lapNumbers(in text: String) -> [Int] {
        text.components(separatedBy: "Lap ").dropFirst().compactMap { Int($0.prefix { $0.isNumber }) }
    }
}
