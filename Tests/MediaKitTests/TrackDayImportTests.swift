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
}
