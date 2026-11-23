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

    /// #661: on the session that had just set the personal best, the menu called an older lap the
    /// "personal best here" and another session of the same day the "last visit".
    @Test func whatAnotherSessionIsDependsOnTheOneBeingRead() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let noon = { (day: Double, hour: Double) in
            Date(timeIntervalSince1970: 1_700_049_600 + day * 86_400 + hour * 3_600)
        }
        let first = entry("first", key: "Stadium", best: 43.0, date: noon(0, 0))
        let firstLater = entry("firstLater", key: "Stadium", best: 42.0, date: noon(0, 3))
        let morning = entry("morning", key: "Stadium", best: 41.5, date: noon(30, -2))
        let record = entry("record", key: "Stadium", best: 41.0, date: noon(30, 0))
        let afternoon = entry("afternoon", key: "Stadium", best: 41.8, date: noon(30, 3))
        let all = [first, firstLater, morning, record, afternoon]
        func others(than own: LogbookEntry) -> [LogbookEntry] {
            LogbookReferences.sessions(at: "Stadium", in: all, excluding: own.file.contentHash)
        }

        // The session that holds the personal best: the quickest of the others is only next best,
        // and the last visit is the first day's quicker session, not that afternoon's.
        let best = try #require(LogbookReferences.best(in: others(than: record), besides: record))
        #expect(best.entry.file.contentHash == "morning" && best.standing == .nextBest)
        let last = LogbookReferences.lastVisit(in: others(than: record), before: record, calendar: calendar)
        #expect(last?.file.contentHash == "firstLater")

        // A slower session of the same day: the record is the personal best, the visit the same.
        let held = try #require(LogbookReferences.best(in: others(than: afternoon), besides: afternoon))
        #expect(held.entry.file.contentHash == "record" && held.standing == .personalBest)
        #expect(
            LogbookReferences.lastVisit(in: others(than: afternoon), before: afternoon, calendar: calendar)?
                .file.contentHash == "firstLater")

        // The first day has no visit before it.
        #expect(LogbookReferences.lastVisit(in: others(than: first), before: first, calendar: calendar) == nil)
        // Nothing known of the session being read: the personal best, and the newest day.
        #expect(LogbookReferences.best(in: all, besides: nil)?.standing == .personalBest)
        #expect(LogbookReferences.lastVisit(in: all, before: nil, calendar: calendar)?.file.contentHash == "record")
    }

    @Test func sessionsOfOneDayAreToldApartByTheirTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let base = Date(timeIntervalSince1970: 1_700_006_400)
        let morning = entry("morning", key: "Stadium", best: 41.5, lap: 3, date: base)
        let afternoon = entry("afternoon", key: "Stadium", best: 41.8, lap: 3, date: base.addingTimeInterval(3 * 3_600))
        let another = entry("another", key: "Stadium", best: 44.0, lap: 3, date: base.addingTimeInterval(9 * 86_400))
        let all = [morning, afternoon, another]
        let plain = LogbookReferences.phrase(for: morning, lap: nil)
        let told = LogbookReferences.phrase(for: morning, lap: nil, among: all, calendar: calendar)
        #expect(told != plain && told.count > plain.count, "\(told)")
        #expect(
            told != LogbookReferences.phrase(for: afternoon, lap: nil, among: all, calendar: calendar),
            "two sessions of a day read differently")
        // A day with one session keeps the short form.
        #expect(
            LogbookReferences.phrase(for: another, lap: nil, among: all, calendar: calendar)
                == LogbookReferences.phrase(for: another, lap: nil))
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

    @Test func theSessionsThatCouldShareTheTrackAreThoseOnTheClockBeforeItEnded() {
        let at = { (hours: Double) in Date(timeIntervalSince1970: 1_700_000_000 + hours * 3_600) }
        let all = [
            entry("own", key: "Stadium", best: 44.6, date: at(10)),
            entry("friend", key: "Stadium", best: 44.0, date: at(9.9), car: "GR86"),
            entry("later", key: "Stadium", best: 44.0, date: at(10.6)),
            entry("lastweek", key: "Stadium", best: 44.0, date: at(-160)),
            entry("elsewhere", key: "Thunderhill", best: 40.0, date: at(10)),
            entry("undated", key: "Stadium", best: 40.0, date: nil),
        ]
        let start = at(10).timeIntervalSince1970
        let span = start...(start + 1_200)
        let sharing = LogbookReferences.sharingTheTrack(
            at: "Stadium", during: span, in: all, excluding: "own", path: nil)
        #expect(sharing.map(\.file.contentHash) == ["friend"])
        // Read from a project, the session is known by its path.
        let byPath = LogbookReferences.sharingTheTrack(
            at: "Stadium", during: span, in: all, excluding: nil, path: "/d/own.csv")
        #expect(byPath.map(\.file.contentHash) == ["friend"])
        let nowhere = LogbookReferences.sharingTheTrack(at: "", during: span, in: all, excluding: nil, path: nil)
        #expect(nowhere.isEmpty)
    }

    @Test func theCompileReadsALogbookSessionAsTheReference() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "refs-\(UUID().uuidString)")
        let logbook = Logbook(directory: folder)
        defer { try? FileManager.default.removeItem(at: folder) }
        let fixture = CornerExportsTests.fixture
        let session = try RaceRenderCSVImporter().importSession(at: fixture, options: SessionBuilder.Options())
        let entry = try LogbookEntry.make(session: session, file: fixture, importerID: "racerender-csv", circuitID: nil)
        try logbook.save(entry)
        // Scoped to this test's task (#431): repointing the process-wide logbook raced the suites
        // that run alongside.
        try await ProjectCompiler.$scopedLogbookDirectory.withValue(folder) {
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
}
