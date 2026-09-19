import Foundation
import Testing

@testable import MediaKit

@Suite("Recording gaps from camera clocks")
struct RecordingGapsTests {
    @Test func filesWithoutClocksGiveNoGap() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Fixtures/test-3s.mp4")
        // The synthetic fixture has neither GPS nor a creation date; the join then keeps no gap.
        let pause = await RecordingGaps.pause(between: fixture, and: fixture)
        #expect(pause == nil || (pause ?? 1) <= 0)
    }

    /// Real GoPro files (local only): chapters of one recording butt together; separate
    /// recordings are minutes apart.
    @Test func goProChaptersButtTogetherAndRecordingsLeaveAPause() async throws {
        guard let dir = ProcessInfo.processInfo.environment["OVERLAYGEN_SAMPLES_DIR"] else { return }
        let base = URL(fileURLWithPath: dir)
        let pairs = [("GX010037.MP4", "GX020037.MP4"), ("GX010030.MP4", "GX020030.MP4")]
        for (a, b) in pairs {
            let first = base.appending(path: a)
            let second = base.appending(path: b)
            guard FileManager.default.fileExists(atPath: first.path),
                FileManager.default.fileExists(atPath: second.path)
            else { continue }
            let pause = try #require(await RecordingGaps.pause(between: first, and: second))
            #expect(abs(pause) < 2, "\(a) → \(b): \(pause) s")
        }
        let first = base.appending(path: "GX010030.MP4")
        let next = base.appending(path: "GX010031.MP4")
        if FileManager.default.fileExists(atPath: first.path), FileManager.default.fileExists(atPath: next.path) {
            let pause = try #require(await RecordingGaps.pause(between: first, and: next))
            #expect(pause > 60, "separate recordings: \(pause) s")
        }
    }
}
