import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

/// Finding the circuit in the real Sonoma session: set `ONBOARD_SAMPLES_DIR` to run it.
///
/// The synthetic tests prove the rule on a shape built to demonstrate it. This proves it on a
/// recording nobody made for the purpose: 131,526 samples at about 93 Hz, nine laps, driven out of
/// the pits at the start and back in at the end.
@Suite("Track extent against the reference session")
struct TrackExtentReferenceTests {
    func referenceSession() throws -> TelemetrySession? {
        guard let samples = ProcessInfo.processInfo.environment["ONBOARD_SAMPLES_DIR"] else { return nil }
        let url = URL(fileURLWithPath: samples).appending(path: "session_20260823_163604_sonoma_v3.csv")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try FormatDetector.importSession(at: url)
    }

    @Test func leavesOutTheOutLapAndTheInLapAndNothingElse() throws {
        guard let session = try referenceSession() else { return }
        let latitude = try #require(session[.latitude])
        let keep = TrackExtent.onTrack(in: session)
        #expect(keep.count == latitude.count)

        struct Run {
            let onTrack: Bool
            let start: Double
            let end: Double
        }
        var runs: [Run] = []
        var start = 0
        for index in 1...keep.count where index == keep.count || keep[index] != keep[start] {
            runs.append(
                Run(
                    onTrack: keep[start], start: latitude.times[start],
                    end: latitude.times[min(index, keep.count - 1)]))
            start = index
        }
        let dropped = runs.filter { !$0.onTrack }

        // Exactly two stretches come off: the way out and the way back. Anything more would be
        // holes punched in the circuit, which is what this must not do.
        #expect(dropped.count == 2)

        // The first is everything before the first complete lap began — the paddock and the pit
        // exit. The second is the run in after the last one.
        let firstLap = try #require(session.laps.first { $0.isComplete })
        let lastLap = try #require(session.laps.last { $0.isComplete })
        #expect(dropped.first?.end ?? 0 <= firstLap.start + 5)
        #expect(dropped.last?.start ?? 0 >= (lastLap.end ?? 0) - 60)
        let lastSample = try #require(latitude.times.last)
        #expect(dropped.last?.end ?? 0 >= lastSample - 5)

        // Every complete lap survives whole: a lap with a hole in it would draw as a broken
        // circuit, and is the failure this is really guarding against.
        for lap in session.laps where lap.isComplete {
            guard let end = lap.end else { continue }
            let inside = latitude.times.indices.filter { latitude.times[$0] > lap.start && latitude.times[$0] < end }
            #expect(inside.allSatisfy { keep[$0] }, "lap \(lap.number)")
        }

        // Most of the session is circuit, because that is what the day was for.
        let surviving = Double(keep.filter { $0 }.count) / Double(keep.count)
        #expect(surviving > 0.7 && surviving < 0.9)
    }

    @Test func isFastEnoughToRunWheneverAProjectIsCompiled() throws {
        guard let session = try referenceSession() else { return }
        // Warm, so this measures the work and not the file.
        _ = TrackExtent.onTrack(in: session)
        let started = Date()
        _ = TrackExtent.onTrack(in: session)
        // Remembered, so the second ask is free. Without the memo it is a third of a second, and a
        // plan is built per timeline cut and the editor builds its own on top.
        #expect(Date().timeIntervalSince(started) < 0.02)

        let latitude = try #require(session[.latitude])
        let longitude = try #require(session[.longitude])
        let cold = Date()
        _ = TrackExtent.onTrack(
            latitudes: latitude.values, longitudes: longitude.values, times: latitude.times)
        // Thinning first is what makes this affordable: asking every one of 131,526 samples takes
        // near two minutes, which would have been unusable.
        #expect(Date().timeIntervalSince(cold) < 3)
    }
}
