import Foundation
import TelemetryKit

/// What a logbook entry reads from its session's samples beyond the laps: its standing starts and
/// stops (#553) and how far it drove.
extension LogbookEntry {
    /// What a camera's recording is, by its file: the recordings a day's folder holds beside the
    /// logger's files.
    public static let recordingExtensions: Set<String> = ["mp4", "mov", "360"]

    /// Whether the session was read from a camera's recording — one with GPS in it and no
    /// logger's session of its own (#394) — and not from a logger's file.
    public var isCameraRecording: Bool {
        Self.recordingExtensions.contains(URL(fileURLWithPath: file.path).pathExtension.lowercased())
    }

    /// Whether its standing starts and stops are measured: as the driver asked, else when it is
    /// a logger's file with no laps and no runs.
    ///
    /// A camera's recording is not measured unasked (#677). The rule was any session with no
    /// laps, meant for a straight-line log; but a clip of the paddock or a cut-short out-lap has
    /// no laps either, and arrived measured, its pit-lane launches under the car's personal
    /// bests. A recording that was measured under that rule stays measured — it has numbers, and
    /// that is how it is told from one added since — so the logbook reads as it did.
    public var measuresPerformanceInForce: Bool {
        if let measuresPerformance { return measuresPerformance }
        guard laps.isEmpty else { return false }
        return !isCameraRecording || performance != nil
    }

    /// Its standing starts and stops from `session` when they are measured, else none: what the
    /// session's reading measured, or measured now.
    public mutating func readPerformance(of session: TelemetrySession) {
        performance =
            measuresPerformanceInForce ? session.performance ?? PerformanceRuns.measure(in: session) : nil
    }

    /// How far the session drove, from its distance channel; `nil` without one.
    public static func distance(of session: TelemetrySession) -> Double? {
        guard let channel = session[.distance], let low = channel.minValue, let high = channel.maxValue, high > low
        else { return nil }
        return high - low
    }
}
