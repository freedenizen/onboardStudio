import Foundation
import Testing

@testable import ProjectModel

/// #498: a session's laps are written into its logbook entry when it is added and were never read
/// again, so a RaceChrono session added before the first lap was corrected (#477) kept the laps
/// it was read with. An entry now says which reading its laps are from.
@Suite("Which reading an entry's laps are from (#498)")
struct LapMeasurementTests {
    func entry(importer: String, laps: [LogbookEntry.LapRecord], measurement: Int) -> LogbookEntry {
        var entry = LogbookEntry(
            file: .init(path: "/days/session.csv", contentHash: importer, byteCount: 1, importerID: importer),
            laps: laps)
        entry.lapMeasurement = measurement
        return entry
    }

    static let partialFirst: [LogbookEntry.LapRecord] = [
        .init(number: 1, seconds: 95, isComplete: false), .init(number: 2, seconds: 90, isComplete: true),
        .init(number: 3, seconds: 30, isComplete: false),
    ]
    static let wholeFirst: [LogbookEntry.LapRecord] = [
        .init(number: 1, seconds: 95, isComplete: true), .init(number: 2, seconds: 90, isComplete: true),
    ]

    @Test func anEntryMadeNowIsOfThisReading() {
        let made = LogbookEntry(
            file: .init(path: "/x.csv", contentHash: "x", byteCount: 1, importerID: "racechrono-csv"))
        #expect(made.lapMeasurement == LogbookEntry.lapMeasurement)
        #expect(!made.needsLapReading)
    }

    @Test func anEntryWrittenBeforeTheFieldIsOfTheFirstReading() throws {
        let made = entry(importer: "racechrono-csv", laps: Self.partialFirst, measurement: LogbookEntry.lapMeasurement)
        var root = try #require(
            try JSONSerialization.jsonObject(with: try JSONEncoder().encode(made)) as? [String: Any])
        #expect(root["lapMeasurement"] as? Int == LogbookEntry.lapMeasurement, "always written")
        root["lapMeasurement"] = nil
        let old = try JSONDecoder().decode(LogbookEntry.self, from: try JSONSerialization.data(withJSONObject: root))
        #expect(old.lapMeasurement == 1)
        #expect(old.needsLapReading)
    }

    @Test func onlyAFileTheCorrectionCanChangeIsOffered() {
        // A CSV whose first lap was called partial though it is not lap 0: the lap the fix makes whole.
        #expect(entry(importer: "racechrono-csv", laps: Self.partialFirst, measurement: 1).needsLapReading)
        // An archive: its first lap was whole, and too long.
        #expect(entry(importer: "racechrono-rcz", laps: Self.wholeFirst, measurement: 1).needsLapReading)
        // A file whose first lap was already whole, or is lap 0, or that has no laps: nothing to gain.
        #expect(!entry(importer: "racerender-csv", laps: Self.wholeFirst, measurement: 1).needsLapReading)
        let fromZero: [LogbookEntry.LapRecord] = [.init(number: 0, seconds: 40, isComplete: false)]
        #expect(!entry(importer: "generic-csv", laps: fromZero, measurement: 1).needsLapReading)
        #expect(!entry(importer: "gpx", laps: [], measurement: 1).needsLapReading)
        #expect(!entry(importer: "racechrono-rcz", laps: [], measurement: 1).needsLapReading)
        // Laps the app counted from a start/finish line begin at lap 0, in an archive too: they
        // are not the file's, and reading it again without the line would lose them.
        #expect(!entry(importer: "racechrono-rcz", laps: fromZero, measurement: 1).needsLapReading)
        // And nothing read with this build's reading is offered again.
        let current = entry(
            importer: "racechrono-csv", laps: Self.partialFirst, measurement: LogbookEntry.lapMeasurement)
        #expect(!current.needsLapReading)
    }
}
