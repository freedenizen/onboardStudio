import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

/// Compares the native delta channels with the output of the user's `racechrono_add_deltas.py`
/// (run with the same reference lap) sample by sample. Local files only: set
/// `ONBOARD_SAMPLES_DIR` and `ONBOARD_DELTA_REFERENCE_CSV`.
@Suite("Lap deltas against the reference script")
struct LapDeltaReferenceTests {
    @Test func nativeChannelsMatchTheScriptOutput() throws {
        let environment = ProcessInfo.processInfo.environment
        guard let samples = environment["ONBOARD_SAMPLES_DIR"],
            let reference = environment["ONBOARD_DELTA_REFERENCE_CSV"]
        else { return }
        let source = URL(fileURLWithPath: samples).appending(path: "session_20260823_163604_sonoma_v3.csv")
        let session = try FormatDetector.importSession(at: source)
        let delta = try #require(session[.lapDelta])
        let speed = try #require(session[.speedDelta])
        #expect(LapDeltas.sessionBest(in: session)?.number == 4, "RaceChrono's best lap (1:56.88)")

        // Python's csv module ends the header row with "\r\n", which Swift treats as one character.
        let lines = try String(contentsOf: URL(fileURLWithPath: reference), encoding: .utf8)
            .components(separatedBy: .newlines).filter { !$0.isEmpty }
        let headerIndex = try #require(lines.firstIndex { $0.hasPrefix("timestamp,") })
        let names = lines[headerIndex].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        let lapColumn = try #require(names.firstIndex(of: "lap_number"))
        var timeErrors: [Double] = []
        var speedErrors: [Double] = []
        for line in lines[(headerIndex + 3)...] {
            let cells = line.split(separator: ",", omittingEmptySubsequences: false)
            guard cells.count == names.count, !cells[lapColumn].isEmpty, let time = Double(cells[0]),
                let scriptSpeed = Double(cells[cells.count - 2]), let scriptTime = Double(cells[cells.count - 1]),
                let nativeTime = delta.value(at: time), let nativeSpeed = speed.value(at: time)
            else { continue }
            timeErrors.append(abs(nativeTime - scriptTime))
            speedErrors.append(abs(nativeSpeed * 2.236_936_3 - scriptSpeed))
        }
        try #require(timeErrors.count > 100_000, "compared \(timeErrors.count) rows")
        timeErrors.sort()
        speedErrors.sort()
        let p99Time = timeErrors[timeErrors.count * 99 / 100]
        let p99Speed = speedErrors[speedErrors.count * 99 / 100]
        let medianTime = timeErrors[timeErrors.count / 2]
        print("lapDelta |native − script|: median \(medianTime) s, p99 \(p99Time) s; speed p99 \(p99Speed) mph")
        #expect(p99Time < 0.05, "99 % of rows within 0.05 s (got \(p99Time))")
        #expect(p99Speed < 1.0, "99 % of rows within 1 mph (got \(p99Speed))")
    }
}
