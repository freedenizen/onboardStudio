import Foundation
import TelemetryKit

/// Reading a session's laps into its entry, and the laps the driver leaves out (#554).
extension LogbookEntry {
    /// The reading the laps of an entry are from. 2 (#477): a RaceChrono file's first lap begins
    /// at the first crossing of the line and is a whole lap — read from an `.rcz` archive it had
    /// swallowed the out-lap, and from a CSV it was called partial.
    public static let lapMeasurement = 2

    /// Whether the Logbook should offer to read this entry's file again (#498): it was read
    /// before the first lap was corrected, and it is one the correction can change — an archive,
    /// or a file whose first lap was called partial. A file it cannot change is not offered:
    /// reading it again would cost the time and move nothing. Laps that begin at lap 0 are not
    /// the file's own count but the app's, from a start/finish line; the correction is not about
    /// them, and read again without that line they would be lost.
    public var needsLapReading: Bool {
        guard lapMeasurement < Self.lapMeasurement, let first = laps.first, first.number != 0 else { return false }
        return file.importerID == "racechrono-rcz" || !first.isComplete
    }

    /// Reads the laps of `session` into the entry with this build's reading, and with them what
    /// is worked out from the laps: the best, the optimal and the fastest rolling lap, and the
    /// corners of the best lap, which may be another lap now. Nothing the driver wrote — the car,
    /// the conditions, the notes — is touched.
    public mutating func readLaps(of session: TelemetrySession) {
        // The laps the driver said do not count (#554) are theirs too, and every figure read here
        // leaves them out.
        var session = session
        session.lapMarks = lapMarks
        let stats = SessionStats(session: session)
        // Cones and an off-course are the driver's (#552): a run keeps them when its file is read again.
        let penalties = Dictionary(laps.map { ($0.number, ($0.cones, $0.offCourse)) }, uniquingKeysWith: { a, _ in a })
        laps = session.laps.listed.map { lap in
            let kept = penalties[lap.number]
            return LapRecord(
                number: lap.number, seconds: lap.duration, isComplete: lap.isComplete, cones: kept?.0 ?? 0,
                offCourse: kept?.1 ?? false, notCounted: session.lapMark(of: lap)?.reason)
        }
        bestLap = stats.bestLap?.seconds
        bestLapNumber = stats.bestLap?.number
        optimalLap = stats.optimalLap
        optimalSources = stats.optimalSources
        fastestRollingLap = CoachingReference.fastestRolling.resolve(in: session)?.duration
        lapMeasurement = Self.lapMeasurement
        applyPenalties()
        readCorners(of: session)
        readPerformance(of: session)
    }

    /// Lap `number` of `session` — this entry's file as the Logbook reads it — left out for
    /// `reason`, or counted again when `reason` is `nil` (#554), and the figures read again
    /// without it: the best, optimal and rolling laps, the best lap's corners. `false` when the
    /// session has no such lap or nothing changed.
    @discardableResult
    public mutating func markLap(_ number: Int, as reason: LapMark.Reason?, in session: TelemetrySession) -> Bool {
        guard let lap = session.laps.first(where: { $0.number == number && $0.isListed }) else { return false }
        guard lapMarks.mark(of: lap)?.reason != reason else { return false }
        lapMarks = lapMarks.marking(lap, as: reason)
        readLaps(of: session)
        return true
    }
}
