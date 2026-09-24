import AVFoundation
import XCTest

// ci-shard: 3
/// J24: one lap, laid out for a phone, exported in one step (#151).
final class VerticalClipUITests: OnboardStudioUITestCase {
    @MainActor
    func testTheLapAtThePlayheadExportsAsAVerticalClip() async throws {
        launch()
        addFixtureVideo()
        addFixtureData()
        let folder = Self.exportDirectory
        let before = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])

        menu("Project", "Export Lap as Vertical Clip…")
        let range = app.staticTexts["clip.range"]
        XCTAssertTrue(range.waitForExistence(timeout: Self.timeout), "No vertical clip sheet")
        app.buttons["clip.export"].click()
        XCTAssertTrue(app.buttons["clip.reveal"].waitForExistence(timeout: 90), "The clip did not finish")

        let written = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .subtracting(before).filter { $0.hasSuffix("(vertical).mp4") }
        let name = try XCTUnwrap(written.first, "No vertical clip in \(folder.path)")
        let url = folder.appending(path: name)
        defer { try? FileManager.default.removeItem(at: url) }
        XCTAssertTrue(name.contains("Lap"), "The file is not named for its lap: \(name)")
        // Phone-shaped: 1080 wide, 1920 tall.
        let tracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .video)
        let track = try XCTUnwrap(tracks.first)
        let size = try await track.load(.naturalSize)
        XCTAssertEqual(size.width, 1080)
        XCTAssertEqual(size.height, 1920)
    }
}
