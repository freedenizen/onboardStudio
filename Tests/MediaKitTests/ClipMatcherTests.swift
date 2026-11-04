import Foundation
import ProjectModel
import Testing

@testable import MediaKit

@Suite("Clips matched to sessions (#394)")
struct ClipMatcherTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    static let noon = Date(timeIntervalSince1970: 1_700_000_000)

    func session(_ hash: String, at start: Date?, minutes: Double? = 25) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: "/s/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"), date: start,
            durationSeconds: minutes.map { $0 * 60 })
    }

    func clip(at start: Date?, minutes: Double? = 20) -> ClipRecord {
        ClipRecord(
            path: "/v/GX010001.MP4", byteCount: 1, fingerprint: "f", durationSeconds: minutes.map { $0 * 60 },
            recordedAt: start)
    }

    @Test func theClocksDecideAndTheLargestOverlapWins() {
        let first = session("a", at: Self.noon)
        let second = session("b", at: Self.noon.addingTimeInterval(3_600))
        // A clip starting ten minutes into the first session.
        let early = clip(at: Self.noon.addingTimeInterval(600))
        #expect(ClipMatcher.match(early, to: [first, second])?.id == first.id)
        #expect(ClipMatcher.match(early, to: [first, second])?.by == .clock)
        // A clip straddling the end of the first and the start of the second: more of it in the second.
        let straddling = clip(at: Self.noon.addingTimeInterval(20 * 60), minutes: 60)
        #expect(ClipMatcher.match(straddling, to: [first, second])?.id == second.id)
        // A clip an hour after both: the clocks say no, and the only-session rule does not apply.
        let late = clip(at: Self.noon.addingTimeInterval(4 * 3_600))
        #expect(ClipMatcher.match(late, to: [first, second]) == nil)
        #expect(ClipMatcher.match(late, to: [first]) == nil, "a dated session the clock rules out is not a match")
        // A session with no length still matches a clip that starts inside it… at its start.
        let open = session("c", at: Self.noon, minutes: nil)
        #expect(ClipMatcher.match(clip(at: Self.noon), to: [open])?.id == open.id)
    }

    @Test func withoutClocksTheOnlySessionOfTheDayIsTaken() {
        let undated = session("a", at: nil)
        let clockless = clip(at: nil)
        #expect(ClipMatcher.match(clockless, to: [undated])?.by == .onlySessionThatDay)
        #expect(ClipMatcher.match(clockless, to: [undated, session("b", at: nil)]) == nil)
        #expect(ClipMatcher.match(clockless, to: []) == nil)
        // A clip with a clock and an undated session: the only one there is.
        #expect(ClipMatcher.match(clip(at: Self.noon), to: [undated])?.by == .onlySessionThatDay)
    }

    @Test func aClipIsRecordedFromWhatTheCameraSays() async throws {
        let url = Self.fixtures.appending(path: "test-3s.mp4")
        let record = try await ClipMatcher.record(url, chapters: [])
        #expect(abs((record.durationSeconds ?? 0) - 3) < 0.5, "\(record.durationSeconds ?? -1)")
        #expect(record.recordedAt != nil, "the file's own date when the camera has none")
        #expect(record.clock != nil)
        #expect(!record.hasGPS)
        #expect(record.fingerprint.count == 64 && record.byteCount > 0)
        #expect(record.name == "test-3s.mp4" && record.resolveFile() == url)
        let (again, _) = try ClipMatcher.fingerprint(of: url)
        #expect(again == record.fingerprint, "the fingerprint is of the bytes")
        let other = try ClipMatcher.fingerprint(of: Self.fixtures.appending(path: "test-rot180.mp4")).hex
        #expect(other != record.fingerprint)
        #expect(ClipMatcher.describe(record).contains("3 s"))
        #expect(ClipMatcher.isClip(url) && !ClipMatcher.isClip(Self.fixtures.appending(path: "track.gpx")))
    }
}
