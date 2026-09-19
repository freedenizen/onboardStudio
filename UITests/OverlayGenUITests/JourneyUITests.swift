import AVFoundation
import XCTest

/// J2 and J11: the whole track-day workflow, from an empty project to an exported file.
final class JourneyUITests: OverlayGenUITestCase {
    @MainActor
    func testTrackDayFromVideoToExport() throws {
        launch()
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForExistence(timeout: Self.timeout))

        // 1. Video: the welcome panel goes, the lane shows the clip, the checklist ticks the step.
        addFixtureVideo()
        XCTAssertTrue(app.staticTexts["welcome.title"].waitForNonExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["test-3s"].waitForExistence(timeout: Self.timeout), "No bar on the timeline")
        XCTAssertTrue(sidebarObject("Camera").exists, "A full-frame video object is added with the first video")
        XCTAssertTrue(app.buttons["toolbar.export"].isEnabled)

        // 2. Data: format, channels and laps are read; sync becomes possible.
        addFixtureData()
        XCTAssertTrue(app.buttons["toolbar.sync"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.buttons["toolbar.sync"].isEnabled)
        sidebarInput("racerender-basic").click()
        XCTAssertTrue(app.staticTexts["RaceRender CSV"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.staticTexts["Laps"].exists)
        XCTAssertTrue(app.staticTexts["Lap 1"].exists, "Lap list from the file's lap tags")

        // 3. Gauges: the template from the Project menu (the checklist offers the same).
        menu("Project", "Apply Template", "Classic Dash")
        for label in ["Speed", "RPM", "Map", "G", "Lap", "Best", "Gear", "Camera"] {
            XCTAssertTrue(sidebarObject(label).waitForExistence(timeout: Self.timeout), "Template object “\(label)”")
        }
        sidebarObject("Speed").click()
        XCTAssertTrue(app.staticTexts["Speedometer"].waitForExistence(timeout: Self.timeout))
        let bound = app.popUpButtons.matching(NSPredicate(format: "value == 'racerender-basic'")).firstMatch
        XCTAssertTrue(bound.exists, "The speedometer is bound to the data file")

        // 4. Play, pause, step, go to start. On a slow runner the preview may still be recompiling
        // when Play is pressed, which drops the request, so press again until the playhead moves.
        let play = app.buttons["transport.play"]
        var moved = false
        for _ in 0..<8 where !moved {
            if play.label == "Play" { play.click() }
            let advanced = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value != %@", "0:00.00"), object: transportTime)
            moved = XCTWaiter().wait(for: [advanced], timeout: 6) == .completed
        }
        XCTAssertTrue(moved, "Playback advanced the playhead")
        if play.label == "Pause" { play.click() }
        app.buttons["transport.start"].click()
        expect(transportTime, toRead: "0:00.00")
        app.buttons["transport.stepForward"].click()
        expect(transportTime, toRead: "0:00.03")

        // 5. Export with the defaults: the sheet, the file, its length.
        let before = Date()
        app.buttons["toolbar.export"].click()
        XCTAssertTrue(app.staticTexts["Export Video"].waitForExistence(timeout: Self.timeout))
        XCTAssertTrue(app.popUpButtons.matching(NSPredicate(format: "value == 'Whole project'")).firstMatch.exists)
        app.buttons["export.start"].click()
        XCTAssertTrue(app.buttons["export.reveal"].waitForExistence(timeout: 120), "Export did not finish")
        XCTAssertTrue(app.buttons["Upload to YouTube…"].exists, "Sharing is offered once the file exists")
        app.buttons["export.close"].click()
        let file = try XCTUnwrap(Self.newestExport(since: before, extension: "mp4"), "No exported file")
        let size = try XCTUnwrap(FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int)
        XCTAssertGreaterThan(size, 20_000, "Export is not empty")
        let duration = try Self.duration(of: file)
        XCTAssertEqual(duration, 3, accuracy: 0.2, "Export runs the length of the clip")
    }

    @MainActor
    func testTransparentOverlayExport() throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        menu("Project", "Apply Template", "Minimal")
        XCTAssertTrue(sidebarObject("Lap").waitForExistence(timeout: Self.timeout))
        let before = Date()
        app.buttons["toolbar.export"].click()
        XCTAssertTrue(app.staticTexts["Export Video"].waitForExistence(timeout: Self.timeout))
        // Behind the overlays → Transparent; this needs an alpha codec, which the sheet offers.
        choose("Transparent", inPopUpShowing: "Video")
        if app.popUpButtons.matching(NSPredicate(format: "value == 'H.264'")).firstMatch.exists {
            choose("HEVC with alpha", inPopUpShowing: "H.264")
        }
        app.buttons["export.start"].click()
        XCTAssertTrue(app.buttons["export.reveal"].waitForExistence(timeout: 120), "Export did not finish")
        app.buttons["export.close"].click()
        let file = try XCTUnwrap(Self.newestExport(since: before, extension: "mov"), "Alpha exports are .mov files")
        XCTAssertEqual(try Self.duration(of: file), 3, accuracy: 0.2)
    }

    // MARK: - Files

    static func newestExport(since date: Date, extension ext: String) -> URL? {
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: exportDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return
            files
            .filter { $0.pathExtension == ext }
            .compactMap { url -> (URL, Date)? in
                guard
                    let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                        .contentModificationDate,
                    modified >= date.addingTimeInterval(-5)
                else { return nil }
                return (url, modified)
            }
            .max { $0.1 < $1.1 }?.0
    }

    static func duration(of file: URL) throws -> Double {
        let asset = AVURLAsset(url: file)
        let expectation = XCTestExpectation(description: "duration")
        nonisolated(unsafe) var seconds = 0.0
        Task {
            seconds = (try? await asset.load(.duration).seconds) ?? 0
            expectation.fulfill()
        }
        XCTWaiter().wait(for: [expectation], timeout: 20)
        return seconds
    }
}
