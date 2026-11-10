import Foundation
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
