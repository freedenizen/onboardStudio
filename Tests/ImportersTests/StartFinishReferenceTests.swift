import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

/// The real Sonoma session: set `ONBOARD_SAMPLES_DIR` to run it.
///
/// The line was originally found by hand and is recorded as ground truth:
/// `38.16155, -122.45467, heading 308`.
@Suite("Start/finish against the reference session")
struct StartFinishReferenceTests {
    static let truth = (latitude: 38.16155, longitude: -122.45467, heading: 308.0)

    /// The session with its lap list thrown away, which is what a file with no lap column looks
    /// like: one partial lap covering everything.
    static func withoutLaps(_ session: TelemetrySession) -> TelemetrySession {
        var stripped = session
        let range = session.timeRange
        stripped.laps = [
            Lap(number: 0, start: range?.lowerBound ?? 0, end: range?.upperBound, isComplete: false)
        ]
        return stripped
    }

    func referenceSession() throws -> TelemetrySession? {
        guard let samples = ProcessInfo.processInfo.environment["ONBOARD_SAMPLES_DIR"] else { return nil }
        let url = URL(fileURLWithPath: samples).appending(path: "session_20260823_163604_sonoma_v3.csv")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try FormatDetector.importSession(at: url)
    }

    @Test func theFilesLapNumbersReproduceTheHandFoundLine() throws {
        guard let session = try referenceSession() else { return }
        let suggestion = try #require(StartFinishFinder.suggest(in: session))
        #expect(suggestion.source == .fileLaps)
        #expect(abs(suggestion.line.latitude - Self.truth.latitude) < 1e-4)
        #expect(abs(suggestion.line.longitude - Self.truth.longitude) < 1e-4)
        #expect(abs((suggestion.line.headingDegrees ?? 0) - Self.truth.heading) < 15)
        #expect(suggestion.laps >= 7)
        #expect(suggestion.spread < 0.02)
    }

    @Test func theTraceAloneGetsCloseEnoughToBeWorthCorrecting() throws {
        guard let session = try referenceSession() else { return }
        let stripped = Self.withoutLaps(session)
        let suggestion = try #require(StartFinishFinder.suggest(in: stripped))
        #expect(suggestion.source == .trace)
        // Not the same place as the hand-found line — any point on the circuit is a valid
        // start/finish — but it must give the same number of laps, of the same length.
        #expect(suggestion.laps >= 7)
        #expect(suggestion.spread < 0.05)
    }
}
