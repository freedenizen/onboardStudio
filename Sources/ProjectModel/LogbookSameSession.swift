import Foundation

/// One drive read from two files (#465). RaceChrono exports a session as CSV v2, CSV v3 and
/// .rcz, and a folder often holds more than one of them. The bytes differ, so the content hash
/// calls them different files, and the logbook counted the drive twice.
///
/// The rule is strict on purpose. Two cars logging the same track session, or two loggers in one
/// car, are different sessions and must stay two; a drive exported again after its finish line
/// was corrected has different laps and is a session of its own.
extension LogbookEntry {
    /// How far two readings of one drive may differ. Measured on one real session exported as
    /// .rcz, CSV v2 and CSV v3: the two CSVs read alike to the last digit; the .rcz was 0.04 s
    /// longer, 0.02 m further and equal to a millisecond on every lap both called complete.
    public enum SameSession {
        /// A fraction of a second for a short log, a few tenths in a twenty-minute session.
        public static func durationTolerance(_ seconds: Double) -> Double { max(0.25, seconds * 0.0005) }
        /// A metre, or a ten-thousandth of the distance driven.
        public static func distanceTolerance(_ meters: Double) -> Double { max(1, meters * 0.0001) }
        public static let lapTolerance = 0.02
        /// A CSV dates the session by its header, to the minute; an .rcz by its first sample.
        /// The date only rules out the same numbers on another day.
        public static let dateTolerance: TimeInterval = 86_400
    }

    /// Whether `other` is this drive, read from another file: as long, as far, on the same day,
    /// and with the same time for every lap that both files number alike and call complete.
    /// Which laps are complete is left to each format — one file's out-lap is another's first lap.
    public func isSameSession(as other: LogbookEntry) -> Bool {
        guard let duration = durationSeconds, let otherDuration = other.durationSeconds,
            abs(duration - otherDuration) <= SameSession.durationTolerance(max(duration, otherDuration))
        else { return false }
        switch (distanceMeters, other.distanceMeters) {
        case (nil, nil): break
        case (let distance?, let otherDistance?):
            guard abs(distance - otherDistance) <= SameSession.distanceTolerance(max(distance, otherDistance))
            else { return false }
        default: return false
        }
        if let date, let otherDate = other.date, abs(date.timeIntervalSince(otherDate)) > SameSession.dateTolerance {
            return false
        }
        let theirs = Dictionary(
            other.laps.filter(\.isComplete).compactMap { lap in lap.seconds.map { (lap.number, $0) } },
            uniquingKeysWith: { first, _ in first })
        return laps.allSatisfy { lap in
            guard lap.isComplete, let seconds = lap.seconds, let their = theirs[lap.number] else { return true }
            return abs(seconds - their) <= SameSession.lapTolerance
        }
    }
}

extension Logbook {
    /// The entry already in the logbook that is the drive `entry` was read from, in another file.
    public func entry(sameSessionAs entry: LogbookEntry) -> LogbookEntry? {
        entries().first { $0.id != entry.id && $0.isSameSession(as: entry) }
    }
}
