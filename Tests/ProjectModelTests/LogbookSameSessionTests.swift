import Foundation
import Testing

@testable import ProjectModel

@Suite("One drive read from two files (#465)")
struct LogbookSameSessionTests {
    typealias Lap = LogbookEntry.LapRecord

    /// The laps of an invented session — no real log's numbers: an out-lap, three timed laps, an
    /// in-lap.
    static let laps = [
        Lap(number: 1, seconds: 131.4, isComplete: false), Lap(number: 2, seconds: 108.72, isComplete: true),
        Lap(number: 3, seconds: 109.35, isComplete: true), Lap(number: 4, seconds: 107.96, isComplete: true),
        Lap(number: 5, seconds: 152.1, isComplete: false),
    ]

    func entry(
        start: TimeInterval = 1_800_000_000, duration: Double? = 1260.5, distance: Double? = 28_450.3,
        laps: [Lap] = LogbookSameSessionTests.laps
    ) -> LogbookEntry {
        LogbookEntry(
            file: .init(
                path: "/logs/\(UUID().uuidString).csv", contentHash: UUID().uuidString, byteCount: 1, importerID: "x"),
            date: Date(timeIntervalSince1970: start), laps: laps, distanceMeters: distance, durationSeconds: duration)
    }

    /// What the .rcz of a session read against its CSV, in kind: dated by its first sample rather
    /// than the header's minute, a few hundredths longer and further, the out-lap called complete
    /// and timed from the start of the log, the in-lap a few thousandths out.
    @Test func anotherExportOfTheDriveIsTheSameSession() {
        var other = Self.laps
        other[0] = Lap(number: 1, seconds: 402.75, isComplete: true)
        other[4] = Lap(number: 5, seconds: 152.093, isComplete: false)
        let csv = entry()
        let rcz = entry(start: 1_800_000_058.2, duration: 1260.54, distance: 28_450.32, laps: other)
        #expect(csv.isSameSession(as: rcz))
        #expect(rcz.isSameSession(as: csv))
        // And a second CSV format, which read alike to the last digit.
        #expect(csv.isSameSession(as: entry()))
    }

    @Test func anotherCarOrAnotherLoggerIsAnotherSession() {
        let mine = entry()
        // In the same track session: started within the minute, a few seconds and metres apart.
        #expect(!mine.isSameSession(as: entry(start: 1_800_000_020, duration: 1255.9)))
        #expect(!mine.isSameSession(as: entry(distance: 28_484.8)))
        // A second logger in the same car agrees to a few hundredths a lap, not to the last one.
        var close = Self.laps
        close[2] = Lap(number: 3, seconds: 109.39, isComplete: true)
        #expect(!mine.isSameSession(as: entry(laps: close)))
    }

    @Test func theDriveExportedAgainWithItsLapsCorrectedIsItsOwnSession() {
        // The finish line moved: as long and as far, every lap different.
        let moved = Self.laps.map {
            Lap(number: $0.number, seconds: $0.seconds.map { $0 + 1.5 }, isComplete: $0.isComplete)
        }
        #expect(!entry().isSameSession(as: entry(laps: moved)))
    }

    @Test func theSameNumbersOnAnotherDayAreAnotherSession() {
        #expect(!entry().isSameSession(as: entry(start: 1_800_000_000 + 2 * 86_400)))
    }

    @Test func aSessionWhoseLengthOrDistanceIsUnknownIsNeverTakenForAnother() {
        // An entry made before the length was kept, and a log with no distance beside one with.
        #expect(!entry().isSameSession(as: entry(duration: nil)))
        #expect(!entry(duration: nil).isSameSession(as: entry(duration: nil)))
        #expect(!entry().isSameSession(as: entry(distance: nil)))
        // Two logs without GPS are judged by their length and laps.
        #expect(entry(distance: nil).isSameSession(as: entry(distance: nil)))
    }

    @Test func aShortLogIsHeldToAQuarterOfASecondAndAMetre() {
        let short = entry(duration: 1.4, distance: 32.2, laps: [])
        #expect(short.isSameSession(as: entry(duration: 1.6, distance: 32.9, laps: [])))
        #expect(!short.isSameSession(as: entry(duration: 1.6, distance: 43.68, laps: [])))
        #expect(!short.isSameSession(as: entry(duration: 1.7, distance: 32.2, laps: [])))
    }

    @Test func theLogbookFindsTheOtherFileOfADrive() throws {
        let logbook = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "same-session-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let first = entry()
        try logbook.save(first)
        try logbook.save(entry(start: 1_800_000_000 - 30 * 86_400, duration: 900, distance: 20_000))
        #expect(logbook.entry(sameSessionAs: entry())?.id == first.id)
        // Not itself, and not a different drive.
        #expect(logbook.entry(sameSessionAs: first) == nil)
        #expect(logbook.entry(sameSessionAs: entry(duration: 1200)) == nil)
    }
}
