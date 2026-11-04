import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

@Suite("Logbook sessions as coaching references (#352)", .serialized)
struct LogbookReferencesTests {
    func entry(_ hash: String, key: String, best: Double?, lap: Int? = 3, date: Date?, car: String = "")
        -> LogbookEntry
    {
        LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"), trackName: key,
            date: date, car: car, bestLap: best, bestLapNumber: best == nil ? nil : lap)
    }

    @Test func theCandidatesAreTheOtherSessionsAtTheCircuit() throws {
        let day = { (n: Double) in Date(timeIntervalSince1970: 1_700_000_000 + n * 86_400) }
        let all = [
            entry("own", key: "Stadium", best: 44.6, date: day(10)),
            entry("pb", key: "Stadium", best: 41.2, lap: 4, date: day(3), car: "Miata"),
            entry("last", key: "Stadium", best: 43.0, date: day(8)),
            entry("nolaps", key: "Stadium", best: nil, date: day(9)),
            entry("elsewhere", key: "Thunderhill", best: 40.0, date: day(9)),
        ]
        let candidates = LogbookReferences.sessions(at: "Stadium", in: all, excluding: "own")
        #expect(Set(candidates.map(\.file.contentHash)) == ["pb", "last"])
        #expect(LogbookReferences.personalBest(in: candidates)?.file.contentHash == "pb")
        #expect(LogbookReferences.lastVisit(in: candidates)?.file.contentHash == "last")
        let pb = try #require(candidates.first { $0.file.contentHash == "pb" })
        #expect(LogbookReferences.phrase(for: pb, lap: nil).hasPrefix("Stadium, "))
        #expect(LogbookReferences.phrase(for: pb, lap: nil).hasSuffix(", lap 4"))
        #expect(LogbookReferences.phrase(for: pb, lap: 2).hasSuffix(", lap 2"))
    }

    @Test func theCompileReadsALogbookSessionAsTheReference() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "refs-\(UUID().uuidString)")
        let logbook = Logbook(directory: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = CornerExportsTests.fixture
        let session = try RaceRenderCSVImporter().importSession(at: fixture, options: SessionBuilder.Options())
        let entry = try LogbookEntry.make(session: session, file: fixture, importerID: "racerender-csv", circuitID: nil)
        try logbook.save(entry)
        let previous = ProjectCompiler.logbookDirectory
        ProjectCompiler.logbookDirectory = folder
        defer { ProjectCompiler.logbookDirectory = previous }
        #expect(LogbookReferences.load(entry)?.laps.count == 4)
        #expect(LogbookReferences.profile(of: entry, lap: nil, session: session)?.label == "Lap 4")

        let data = Input(label: "d", source: MediaReference(path: fixture.path), kind: .data(DataInputSettings()))
        var loaded = try CornerExportsTests.loaded(lap: 2)
        loaded.project.inputs = [data]
        loaded.sessions = [data.id: session]
        loaded.project.coaching = CoachingSettings(
            dataInputID: data.id, lap: 2, reference: .logbook(entryID: entry.id, lap: 4))
        let tracks = CoachingTracks.make(for: loaded.project, sessions: loaded.sessions, previous: nil)
        let track = try #require(tracks[data.id])
        #expect(track.referencePhrase.hasPrefix("coaching-laps") && track.referencePhrase.hasSuffix("lap 4"))
        #expect(track.reference.label == "Lap 4")
        // Another session, so lined up by position, as another file's lap is.
        #expect(track.analyses[2]?.delta.alignment == .byPosition)
        // A session the logbook has lost falls back to the session best.
        loaded.project.coaching = CoachingSettings(
            dataInputID: data.id, lap: 2, reference: .logbook(entryID: UUID(), lap: nil))
        let fallback = CoachingTracks.make(for: loaded.project, sessions: loaded.sessions, previous: nil)
        #expect(fallback[data.id]?.referencePhrase == "your best lap")
    }
}
