import AVFoundation
import XCTest

// ci-shard: 1
/// J34: the session's coaching debrief as one video — cards and the corners that cost the most,
/// from one menu item (#327).
final class DebriefUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheDebriefExportsAsOneVideo() async throws {
        launch()
        addFixtureVideo()
        testing("Add Fixture Data (Coaching Laps)")
        XCTAssertTrue(sidebarInput("coaching-laps").waitForExistence(timeout: Self.timeout), "No fixture data")
        let folder = Self.exportDirectory
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])

        menu("Project", "Export Coaching Debrief…")
        let export = app.buttons["debrief.export"]
        XCTAssertTrue(export.waitForExistence(timeout: Self.timeout), "No debrief sheet")
        // The sheet lists what it will write once the laps are read: the cards at least.
        let segments = app.descendants(matching: .any).matching(identifier: "debrief.segments").firstMatch
        XCTAssertTrue(segments.waitForExistence(timeout: Self.timeout * 2), "The debrief was not planned")
        let listed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: export)
        XCTAssertEqual(XCTWaiter().wait(for: [listed], timeout: Self.timeout), .completed, "Export never enabled")
        export.click()
        XCTAssertTrue(app.buttons["debrief.reveal"].waitForExistence(timeout: 120), "The debrief did not finish")

        let written = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .subtracting(before).filter { $0.hasSuffix("Coaching Debrief.mp4") }
        let name = try XCTUnwrap(written.first, "No debrief in \(folder.path)")
        let url = folder.appending(path: name)
        defer { try? FileManager.default.removeItem(at: url) }
        // One playable file, at least as long as the two cards.
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        XCTAssertGreaterThanOrEqual(duration, 9.5, "A title card and a closing card play for ten seconds")
        let tracks = try await asset.loadTracks(withMediaType: .video)
        XCTAssertEqual(tracks.count, 1)
    }
}
