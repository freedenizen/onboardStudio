import Foundation
import Importers
import ProjectModel
import Testing

@testable import MediaKit

@Suite("Add Track Day (#346)", .serialized)
struct TrackDayImportTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "trackday-\(UUID().uuidString)"))
    }

    @Test func aFolderYieldsItsTelemetryFilesAndClipsButNotTheRest() {
        let files = TrackDayImport.files(in: [Self.fixtures])
        let names = Set(files.map(\.lastPathComponent))
        #expect(names.contains("coaching-laps.csv"))
        #expect(names.contains("racechrono-v3.csv"))
        #expect(names.contains("track.gpx"))
        #expect(names.contains("session.vbo"))
        #expect(names.contains("session.rcz"))
        #expect(names.contains("test-3s.mp4"))
        #expect(!names.contains("arrow.png"))
        #expect(!names.contains("README.md"))
        #expect(!names.contains("project.json"), "a project package is not opened")
        #expect(!names.contains { $0.hasSuffix(".png") })
        // A single file is taken as it is; a missing one is left out.
        #expect(TrackDayImport.files(in: [Self.fixtures.appending(path: "track.gpx")]).count == 1)
        #expect(TrackDayImport.files(in: [Self.fixtures.appending(path: "nope.csv")]).isEmpty)
    }

    @Test func aTrackDayIsEnteredOnceAndSkippedTheSecondTime() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var seen: [String] = []
        let reports = await TrackDayImport.run([Self.fixtures], into: logbook, car: "Miata") { index, count, url in
            #expect(index < count)
            _ = url
        }
        seen = reports.map(\.line)
        let added = reports.filter(\.isAdded)
        #expect(added.count >= 6, "\(seen)")
        #expect(logbook.entries().count == added.count)
        // No two fixtures are taken for one drive (#465): each is a session of its own.
        #expect(!reports.contains { if case .sameSession = $0.outcome { true } else { false } }, "\(seen)")
        for report in added {
            guard case .added(let entry) = report.outcome else { continue }
            #expect(entry.car == "Miata")
            #expect(entry.file.contentHash.count == 64)
            #expect(entry.file.path == report.url.path)
            #expect(report.line.contains("added"))
        }
        // The RaceChrono fixture read its laps and its date.
        let racechrono = try #require(reports.first { $0.url.lastPathComponent == "racechrono-v3.csv" })
        guard case .added(let entry) = racechrono.outcome else {
            Issue.record("racechrono-v3.csv not added")
            return
        }
        #expect(!entry.laps.isEmpty)
        #expect(entry.file.importerID == "racechrono-csv")
        // A picture is not in the list at all; a clip without GPS is reported, not added.
        #expect(!reports.contains { $0.url.lastPathComponent == "arrow.png" })
        if let clip = reports.first(where: { $0.url.lastPathComponent == "test-3s.mp4" }) {
            #expect(!clip.isAdded)
        }
        // The same files again: every one already there, nothing added twice.
        let again = await TrackDayImport.run([Self.fixtures], into: logbook)
        #expect(again.filter(\.isAdded).isEmpty)
        let skipped = again.filter { if case .alreadyThere = $0.outcome { return true } else { return false } }
        #expect(skipped.count == added.count)
        #expect(logbook.entries().count == added.count)
        #expect(again.first { $0.url.lastPathComponent == "racechrono-v3.csv" }?.line.contains("already in") == true)
    }

    /// The v2 fixture's drive as RaceChrono's CSV v3 would export it: the same samples and laps
    /// under the other format's columns.
    static let v3Twin = """
        This file is created using RaceChrono Pro v10.2.4 ( http://racechrono.com/ ).
        Format,3
        Session title,"Test Circuit"
        Session type,Lap timing
        Track name,"Test Circuit"
        Driver name,
        Created,23/08/2026,23:35
        Note,

        timestamp,fragment_id,lap_number,elapsed_time,distance_traveled,latitude,longitude,speed
        unix time,,,s,m,deg,deg,m/s
        ,,,,,100: gps,100: gps,100: gps
        1787528164.60,0,,0.00,0.0,45.0000000,-122.0000000,20.0
        1787528164.80,0,,0.20,4.0,45.0000360,-122.0000000,21.0
        1787528165.00,0,1,0.40,8.2,45.0000720,-122.0000000,22.0
        1787528165.20,0,1,0.60,12.6,45.0000720,-122.0000560,23.0
        1787528165.40,0,1,0.80,17.2,45.0000720,-122.0001120,24.0
        1787528165.60,0,2,1.00,22.0,45.0000720,-122.0001680,25.0
        1787528165.80,0,2,1.20,27.0,45.0000360,-122.0001680,26.0
        1787528166.00,0,2,1.40,32.2,45.0000000,-122.0001680,27.0

        """

    /// #465: a folder with one drive exported twice — RaceChrono's CSV v2 and v3 — is one session,
    /// and the second file's line says which file the logbook has it from.
    @Test func theSameSessionInASecondFormatIsNotAddedAgain() async throws {
        let logbook = temporaryLogbook()
        let folder = FileManager.default.temporaryDirectory.appending(path: "twins-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: logbook.directory)
            try? FileManager.default.removeItem(at: folder)
        }
        let v2 = folder.appending(path: "session_v2.csv")
        let v3 = folder.appending(path: "session_v3.csv")
        try FileManager.default.copyItem(at: Self.fixtures.appending(path: "racechrono-v2.csv"), to: v2)
        try Self.v3Twin.write(to: v3, atomically: true, encoding: .utf8)

        let reports = await TrackDayImport.run([folder], into: logbook)
        let lines = reports.map(\.line)
        #expect(reports.count == 2, "\(lines)")
        #expect(reports.filter(\.isAdded).map(\.url.lastPathComponent) == ["session_v2.csv"], "\(lines)")
        let second = try #require(reports.first { $0.url.lastPathComponent == "session_v3.csv" })
        guard case .sameSession(let existing) = second.outcome else {
            Issue.record("The v3 export was not recognised as the v2 export's session: \(lines)")
            return
        }
        #expect(second.isAlreadyThere && !second.isAdded)
        #expect(second.line.contains("the same session as session_v2.csv"), "\(second.line)")
        #expect(logbook.entries().map(\.id) == [existing.id])
        #expect(logbook.days().count == 1, "The file that was not added made no day of its own")

        // Added to a project, the second file is the session the logbook already has (#349).
        let session = try FormatDetector.importSession(at: v3)
        let enrolment = try ProjectLogbook.enter(.init(url: v3, session: session), into: logbook)
        #expect(!enrolment.isNew && enrolment.entry.id == existing.id)
        #expect(logbook.entries().count == 1)

        // A different drive in the same folder is still its own session.
        let other = folder.appending(path: "other.csv")
        try FileManager.default.copyItem(at: Self.fixtures.appending(path: "racechrono-v3.csv"), to: other)
        let again = await TrackDayImport.run([folder], into: logbook)
        #expect(again.filter(\.isAdded).map(\.url.lastPathComponent) == ["other.csv"], "\(again.map(\.line))")
        #expect(logbook.entries().count == 2)
    }

    @Test func filesGoOnTheChosenDayOrOnTheDayTheySay() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        // Onto a day begun first: its car and driver, its conditions, its id (#393).
        var day = TrackDay(date: Date(timeIntervalSince1970: 1_700_000_000), trackName: "Fixtures", car: "GR86")
        day.driver = "Sam"
        day.conditions = SessionConditions(weather: .rain, track: .wet)
        try logbook.saveDay(day)
        let chosen = await TrackDayImport.run(
            [Self.fixtures.appending(path: "racechrono-v3.csv")], into: logbook, day: day)
        let onDay = try #require(chosen.first { $0.isAdded })
        guard case .added(let entry) = onDay.outcome else { return }
        #expect(entry.trackDayID == day.id)
        #expect(entry.car == "GR86" && entry.driver == "Sam")
        #expect(entry.conditions.weather == .rain, "the day's conditions, to begin with")
        #expect(onDay.dayLabel == nil && !onDay.line.contains(", in "), "a chosen day is not announced")
        #expect(logbook.sessions(of: day).count == 1)
        // Without a day: onto the one its date and circuit say, made if need be, and the line says which.
        let free = await TrackDayImport.run([Self.fixtures.appending(path: "coaching-laps.csv")], into: logbook)
        let placed = try #require(free.first { $0.isAdded })
        guard case .added(let other) = placed.outcome else { return }
        let madeDay = try #require(other.trackDayID.flatMap { logbook.day(id: $0) })
        #expect(madeDay.id != day.id, "a different circuit and date: its own day")
        #expect(placed.dayLabel == madeDay.label)
        #expect(placed.line.hasSuffix(", in \(madeDay.label)"))
        #expect(logbook.days().count == 2)
    }

    /// #468: a video exported from a session's project, offered with the day's files, is the
    /// finished overlay and not that session's picture.
    @Test func aVideoTheAppExportedIsNotTakenForARecording() async throws {
        let logbook = temporaryLogbook()
        let folder = FileManager.default.temporaryDirectory.appending(path: "exports-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: logbook.directory)
            try? FileManager.default.removeItem(at: folder)
        }
        let day = TrackDay(date: Date(timeIntervalSince1970: 1_700_000_000), trackName: "Fixtures")
        try logbook.saveDay(day)
        _ = await TrackDayImport.run([Self.fixtures.appending(path: "racechrono-v3.csv")], into: logbook, day: day)
        let export = folder.appending(path: "overlay.mp4")
        try FileManager.default.copyItem(at: Self.fixtures.appending(path: "test-3s.mp4"), to: export)
        let session = try #require(logbook.entries().first)
        ProjectLogbook.record(export: export, in: [session.id], logbook: logbook)

        let reports = await TrackDayImport.run([folder], into: logbook, day: day)
        let report = try #require(reports.first)
        guard case .ownExport(let source) = report.outcome else {
            Issue.record("the export was taken for a recording: \(report.line)")
            return
        }
        #expect(source.id == session.id)
        #expect(!report.isClip && !report.isAdded)
        #expect(report.line.contains("not added: a video exported from"), Comment(rawValue: report.line))
        #expect(logbook.day(id: day.id)?.clips.isEmpty == true, "nothing was put on the day")
        // The same file with no export recorded on any session is a clip like any other.
        let other = folder.appending(path: "camera.mp4")
        try FileManager.default.copyItem(at: Self.fixtures.appending(path: "test-3s.mp4"), to: other)
        let again = await TrackDayImport.run([other], into: logbook, day: day)
        #expect(again.first?.isClip == true, "\(again.map(\.line))")
    }

    @Test func aClipGoesOnTheDayAndIsMatchedOrLeftToAssign() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = TrackDay(date: Date(timeIntervalSince1970: 1_700_000_000), trackName: "Fixtures")
        try logbook.saveDay(day)
        // A dated session the clip's file date is nowhere near: the clip is kept, unassigned.
        _ = await TrackDayImport.run([Self.fixtures.appending(path: "racechrono-v3.csv")], into: logbook, day: day)
        let reports = await TrackDayImport.run([Self.fixtures.appending(path: "test-3s.mp4")], into: logbook, day: day)
        let report = try #require(reports.first)
        #expect(report.isClip && !report.isAdded)
        guard case .clip(let clip, let session) = report.outcome else {
            Issue.record("not a clip: \(report.line)")
            return
        }
        #expect(session == nil && clip.sessionID == nil)
        #expect(
            report.line.contains("video") && report.line.contains("assign it in the logbook"),
            Comment(rawValue: report.line))
        let kept = try #require(logbook.day(id: day.id))
        #expect(kept.clips.count == 1 && kept.clips[0].name == "test-3s.mp4")
        #expect(logbook.entries().count == 1, "a clip without GPS is not a session")
        // Again: already on the day.
        let again = await TrackDayImport.run([Self.fixtures.appending(path: "test-3s.mp4")], into: logbook, day: day)
        #expect(again.first?.line.hasSuffix("video already on the day") == true)
        #expect(logbook.day(id: day.id)?.clips.count == 1)
        // On a day whose one session is undated, the clip is that session's.
        let other = TrackDay(date: Date(timeIntervalSince1970: 1_600_000_000), trackName: "Elsewhere")
        try logbook.saveDay(other)
        var undated = LogbookEntry(
            file: .init(path: "/s/u.csv", contentHash: "u", byteCount: 1, importerID: "x"), car: "Miata")
        undated.trackDayID = other.id
        try logbook.save(undated)
        let matched = await TrackDayImport.run(
            [Self.fixtures.appending(path: "test-rot180.mp4")], into: logbook, day: other)
        guard case .clip(let second, let owner) = try #require(matched.first).outcome else { return }
        #expect(owner?.id == undated.id && second.matchedBy == .onlySessionThatDay)
        #expect(matched.first?.line.contains("the picture of") == true)
    }
}
