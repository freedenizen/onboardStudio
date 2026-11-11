import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #498 through the files: an entry as a build before #477 wrote it is read again, and comes to
/// what the same file gives when it is added now — with everything the driver wrote left alone.
@Suite("Reading an old entry's laps again (#498)", .serialized)
struct LapReadingAgainTests {
    static let csv = TrackDayImportTests.fixtures.appending(path: "racechrono-v2.csv")

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "lapreading-\(UUID().uuidString)"))
    }

    /// The fixture entered, then put back to what the old reading wrote.
    func oldEntry(in logbook: Logbook) async throws -> (old: LogbookEntry, fresh: LogbookEntry) {
        _ = await TrackDayImport.run([Self.csv], into: logbook)
        let fresh = try #require(logbook.entries().first)
        var old = fresh
        let session = try FormatDetector.importSession(
            at: Self.csv, options: SessionBuilder.Options(legacyFirstLap: true))
        old.readLaps(of: session)
        old.lapMeasurement = 1
        old.car = "Miata"
        old.notes = "Cold tyres."
        old.conditions = SessionConditions(weather: .rain, track: .wet)
        try logbook.save(old)
        return (old, fresh)
    }

    @Test func anOldEntryComesToWhatTheFileGivesNow() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let (old, fresh) = try await oldEntry(in: logbook)
        // As the old build left it: the first lap partial, one complete lap fewer.
        #expect(old.needsLapReading)
        #expect(old.laps.first?.isComplete == false)
        #expect(old.completeLapCount == fresh.completeLapCount - 1)

        #expect(LogbookReferences.readLapsAgain(of: [old.id], in: logbook).isEmpty)
        let read = try #require(logbook.entry(id: old.id))
        #expect(read.laps == fresh.laps && read.bestLap == fresh.bestLap && read.bestLapNumber == fresh.bestLapNumber)
        #expect(read.optimalLap == fresh.optimalLap && read.fastestRollingLap == fresh.fastestRollingLap)
        #expect(read.lapMeasurement == LogbookEntry.lapMeasurement && !read.needsLapReading)
        // What the driver wrote is still there.
        #expect(read.car == "Miata" && read.notes == "Cold tyres." && read.conditions.weather == .rain)
        #expect(read.id == old.id && read.trackDayID == old.trackDayID)
        // Asked again, there is nothing left to do.
        #expect(LogbookReferences.readLapsAgain(of: [old.id], in: logbook).isEmpty)
        #expect(logbook.entry(id: old.id) == read)
    }

    @Test func anEntryWhoseFileIsGoneIsLeftAsItWas() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var (old, _) = try await oldEntry(in: logbook)
        old.file.path = "/nowhere/session.csv"
        old.file.bookmark = nil
        try logbook.save(old)
        #expect(LogbookReferences.readLapsAgain(of: [old.id], in: logbook) == [old.id])
        let kept = try #require(logbook.entry(id: old.id))
        #expect(kept.laps == old.laps && kept.lapMeasurement == 1, "still offered when the file is back")
    }
}
