import Foundation
import TelemetryKit
import Testing

@testable import ProjectModel

/// Cones and DNFs (#552): what a run's time counts as, and what that does to the session's best.
@Suite struct RunPenaltyTests {
    typealias Record = LogbookEntry.LapRecord

    /// Runs of 50, 51 and 49.5 s, the last never reaching the finish.
    static func entry(penaltyPerCone: Double? = nil) -> LogbookEntry {
        var entry = LogbookEntry(
            file: .init(path: "/tmp/runs.vbo", contentHash: UUID().uuidString, byteCount: 1, importerID: "vbo"),
            date: Date(timeIntervalSince1970: 1_800_000_000),
            laps: [
                Record(number: 1, seconds: 50, isComplete: true), Record(number: 2, seconds: 51, isComplete: true),
                Record(number: 3, seconds: 49.5, isComplete: false),
            ])
        entry.runLines = RunLines(
            start: LapLineSpec(latitude: 47, longitude: 8), finish: LapLineSpec(latitude: 47.001, longitude: 8))
        entry.penaltyPerCone = penaltyPerCone
        entry.applyPenalties()
        return entry
    }

    @Test func theOfficialTimeIsTheClockPlusTheCones() {
        let run = Record(number: 1, seconds: 50, isComplete: true, cones: 2)
        #expect(run.officialSeconds(perCone: 2) == 54)
        #expect(Record(number: 2, seconds: 50, isComplete: true, offCourse: true).officialSeconds(perCone: 2) == nil)
        #expect(Record(number: 3, seconds: 49, isComplete: false).officialSeconds(perCone: 2) == nil)
    }

    @Test func theBestRunIsTheQuickestThatCounts() {
        var entry = Self.entry()
        #expect(entry.bestLap == 50 && entry.bestLapNumber == 1, "the DNF's 49.5 s does not count")
        entry.laps[0].cones = 1
        entry.applyPenalties()
        #expect(entry.bestLap == 51 && entry.bestLapNumber == 2, "a cone on run 1 makes run 2 the best")
        entry.laps[1].offCourse = true
        entry.applyPenalties()
        #expect(entry.bestLap == 52 && entry.bestLapNumber == 1, "run 2 off course leaves run 1 and its cone")
    }

    @Test func aDaysPenaltyReachesItsRuns() throws {
        let logbook = Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "cones-\(UUID())"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var entry = Self.entry()
        entry.laps[0].cones = 1
        entry.applyPenalties()
        let day = try logbook.assignDay(to: &entry)
        try logbook.save(entry)
        #expect(entry.bestLapNumber == 2, "52 s against 51 s at 2 s a cone")
        var changed = day
        changed.penaltyPerCone = 0.5
        try logbook.updateDay(changed)
        let after = try #require(logbook.entry(id: entry.id))
        #expect(after.penaltyPerCone == 0.5)
        #expect(after.bestLap == 50.5 && after.bestLapNumber == 1, "50.5 s against 51 s at half a second")
    }

    @Test func readingTheFileAgainKeepsTheConesAndOffCourse() {
        var entry = Self.entry()
        entry.laps[0].cones = 3
        entry.laps[1].offCourse = true
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"), channels: [],
            laps: [
                Lap(number: 1, start: 0, end: 50, isComplete: true, kind: .run),
                Lap(number: 2, start: 60, end: 111, isComplete: true, kind: .run),
            ])
        entry.readLaps(of: session)
        #expect(entry.laps.map(\.cones) == [3, 0])
        #expect(entry.laps.map(\.offCourse) == [false, true])
        #expect(entry.bestLap == 56, "run 1 and its three cones is all that counts")
    }

    @Test func theEditsAreNamedForUndo() {
        let entry = Self.entry()
        var coned = entry
        coned.laps[0].cones = 1
        #expect(LogbookEditName.of(entry, coned) == "Change Cones")
        var off = entry
        off.laps[0].offCourse = true
        #expect(LogbookEditName.of(entry, off) == "Mark Off Course")
        #expect(LogbookEditName.of(off, entry) == "Mark Run Finished")
    }

    @Test func aLapWrittenBeforeConesHasNone() throws {
        let json = Data(#"{"number":2,"seconds":51.2,"isComplete":true}"#.utf8)
        let lap = try JSONDecoder().decode(Record.self, from: json)
        #expect(lap.cones == 0 && !lap.offCourse)
    }

    @Test func theExportsSayWhatCounts() {
        var entry = Self.entry()
        entry.laps[0].cones = 2
        entry.applyPenalties()
        let markdown = LogbookTransfer.markdown([entry])
        #expect(markdown.contains("- Run 1: 0:50.00 + 2 cones = 0:54.00"), "\(markdown)")
        #expect(markdown.contains("- Run 3: 0:49.50 (DNF)"))
        let csv = LogbookTransfer.lapsCSV([entry])
        #expect(csv.hasPrefix("date,circuit,car,lap,seconds,complete,cones,official"))
        #expect(csv.contains(",2,54.000"))
    }
}
