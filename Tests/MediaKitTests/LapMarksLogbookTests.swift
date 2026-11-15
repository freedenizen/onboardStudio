import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// Laps left out in the Logbook (#554): the entry's figures are read again without them, and
/// everything that reads those figures — Trends, the personal bests, the goals — follows.
@Suite("Laps that do not count, in the Logbook")
struct LapMarksLogbookTests {
    /// Four laps: 41.2 s, 44.6 s, 41.2 s, 41.2 s.
    static let csv = TrackDayImportTests.fixtures.appending(path: "coaching-laps.csv")

    static func entry() throws -> (LogbookEntry, TelemetrySession) {
        let session = try FormatDetector.importSession(at: csv)
        var entry = LogbookEntry(
            file: .init(path: csv.path, contentHash: UUID().uuidString, byteCount: 1, importerID: "generic-csv"),
            circuitID: "Q1")
        entry.readLaps(of: session)
        return (entry, session)
    }

    @Test func anEntryWithNoMarksReadsAsBefore() throws {
        let (entry, session) = try Self.entry()
        let stats = SessionStats(session: session)
        #expect(entry.lapMarks.isEmpty)
        #expect(entry.laps.allSatisfy { $0.counts })
        #expect(entry.bestLap == stats.bestLap?.seconds)
        #expect(entry.bestLapNumber == stats.bestLap?.number)
        #expect(entry.optimalLap == stats.optimalLap)
        #expect(!entry.optimalSources.isEmpty)
        #expect(LogbookTrends.lapSpread(of: entry) != nil)
    }

    @Test func leavingTheBestLapOutReadsTheFiguresAgain() throws {
        var (entry, session) = try Self.entry()
        let best = try #require(entry.bestLapNumber)
        let original = entry.optimalLap
        let changed = entry.markLap(best, as: .offTrack, in: session)
        #expect(changed)
        #expect(entry.bestLapNumber != best)
        #expect(entry.laps.first { $0.number == best }?.notCounted == .offTrack)
        #expect(!entry.optimalSources.contains(best))
        // Nothing changes when the same mark is made again.
        let again = entry.markLap(best, as: .offTrack, in: session)
        #expect(!again)
        // Leaving out every quick lap leaves the slow one as the best, and a slower optimal.
        let optimal = try #require(entry.optimalLap)
        for lap in entry.laps where lap.number != 2 { entry.markLap(lap.number, as: .traffic, in: session) }
        #expect(entry.bestLapNumber == 2)
        let slower = try #require(entry.bestLap)
        #expect(slower > 44)
        let slowerOptimal = try #require(entry.optimalLap)
        #expect(slowerOptimal > optimal)
        #expect(entry.optimalSources == [2])
        // Counted again, it is as it was.
        for lap in entry.laps where lap.number != 2 { entry.markLap(lap.number, as: nil, in: session) }
        #expect(entry.lapMarks.isEmpty)
        #expect(entry.laps.allSatisfy { $0.counts })
        #expect(entry.optimalLap == original)
    }

    @Test func consistencyAndTrendsLeaveTheLapOut() throws {
        var (entry, session) = try Self.entry()
        let spread = try #require(LogbookTrends.lapSpread(of: entry))
        #expect(spread > 1, "the slow lap widens it")
        entry.markLap(2, as: .traffic, in: session)
        let steady = try #require(LogbookTrends.lapSpread(of: entry))
        #expect(steady < 0.01, "three laps of 41.2 s")
        // Two left out leaves too few to say.
        entry.markLap(1, as: .flag, in: session)
        #expect(LogbookTrends.lapSpread(of: entry) == nil)
        let key = LogbookFilter.circuitKey(of: entry)
        let point = try #require(LogbookTrends.points(for: [entry], circuitKey: key).first)
        #expect(point.best == entry.bestLap)
        #expect(point.spread == nil)
    }

    @Test func theMarksSurviveTheLapsBeingReadAgain() throws {
        var (entry, session) = try Self.entry()
        entry.markLap(3, as: .flag, in: session)
        let marks = entry.lapMarks
        entry.readLaps(of: session)
        #expect(entry.lapMarks == marks)
        #expect(entry.laps.first { $0.number == 3 }?.notCounted == .flag)
    }

    @Test func thePersonalBestIsALapThatCounts() throws {
        var (entry, session) = try Self.entry()
        let before = try #require(PersonalBests.best(in: [entry], circuitKey: LogbookFilter.circuitKey(of: entry)))
        for lap in entry.laps where lap.number != 2 { entry.markLap(lap.number, as: .offTrack, in: session) }
        let after = try #require(PersonalBests.best(in: [entry], circuitKey: LogbookFilter.circuitKey(of: entry)))
        #expect(after.seconds > before.seconds)
    }

    @Test func undoSaysWhichLap() throws {
        var (entry, session) = try Self.entry()
        let before = entry
        entry.markLap(2, as: .traffic, in: session)
        #expect(LogbookEditName.of(before, entry) == "Leave Lap 2 Out")
        let marked = entry
        entry.markLap(2, as: nil, in: session)
        #expect(LogbookEditName.of(marked, entry) == "Count Lap 2")
    }

    @Test func entriesAndLapsWrittenBeforeReadAsCounting() throws {
        let (entry, _) = try Self.entry()
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(entry)) as? [String: Any])
        json.removeValue(forKey: "lapMarks")
        json.removeValue(forKey: "optimalSources")
        json["laps"] = (json["laps"] as? [[String: Any]])?.map { lap in
            var lap = lap
            lap.removeValue(forKey: "notCounted")
            return lap
        }
        let old = try JSONDecoder().decode(LogbookEntry.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(old.lapMarks.isEmpty)
        #expect(old.optimalSources.isEmpty)
        #expect(old.laps.allSatisfy { $0.counts })
        #expect(old.bestLap == entry.bestLap)
        // And a marked entry round-trips.
        var (marked, session) = try Self.entry()
        marked.markLap(2, as: .offTrack, in: session)
        let back = try JSONDecoder().decode(LogbookEntry.self, from: JSONEncoder().encode(marked))
        #expect(back.lapMarks == marked.lapMarks)
        #expect(back.laps == marked.laps)
        #expect(back.optimalSources == marked.optimalSources)
    }

    /// The video counts every lap (#554): a project's marks are read by the Coaching window and
    /// `onboard coach`, never put on the session the project renders.
    @Test func aProjectRendersEveryLap() async throws {
        let data = Input(
            label: "Data", source: MediaReference(path: Self.csv.path), kind: .data(DataInputSettings()))
        var project = Project(inputs: [data])
        let (_, plain) = try Self.entry()
        let best = try #require(LapDeltas.sessionBest(in: plain))
        project.coaching = CoachingSettings(
            dataInputID: data.id, lapMarks: [LapMark(lap: best, reason: .offTrack)])
        let loaded = try await ProjectCompiler.load(
            project, location: ProjectLocation(URL(fileURLWithPath: "/tmp/laps-left-out.onboardproj")))
        let session = try #require(loaded.sessions[data.id])
        #expect(session.lapMarks.isEmpty)
        #expect(LapDeltas.sessionBest(in: session)?.number == best.number)
        #expect(SessionStats(session: session).bestLap?.number == best.number)
    }
}
