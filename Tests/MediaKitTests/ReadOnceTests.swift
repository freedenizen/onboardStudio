import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #482 as the app meets it: a session is added to the logbook, a project is made from it, and
/// Coaching is opened on it — three readers of one unchanged file, and one reading of it. Read
/// through a cache of the test's own: the shared one is read through by every other test in the
/// process, and on CI they pushed this file out of it before the test had looked.
@Suite("The Logbook, a project and Coaching read a file once (#482)", .serialized)
struct ReadOnceTests {
    func copy(of fixture: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "readonce-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fixture)
        try FileManager.default.copyItem(at: TrackDayImportTests.fixtures.appending(path: fixture), to: url)
        return url
    }

    @Test func threeReadersOfOneFileReadItOnce() async throws {
        let file = try copy(of: "racechrono-v2.csv")
        let logbook = Logbook(directory: file.deletingLastPathComponent().appending(path: "Logbook"))
        defer { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
        let id = "racechrono-csv"
        let cache = ParsedFileCache()

        try await ParsedFileCache.$current.withValue(cache) {
            // Added to the logbook.
            _ = await TrackDayImport.run([file], into: logbook)
            let entry = try #require(logbook.entries().first)
            #expect(entry.file.importerID == id)
            #expect(cache.timesRead(file, importerID: id) == 1)

            // A project reads it through its own settings: here, without the first half of the data.
            var settings = DataInputSettings()
            settings.importerID = id
            let asTheLogbookReadIt = try ProjectCompiler.importData(at: file, settings: settings)
            let times = try #require(asTheLogbookReadIt[.speed]).times
            settings.trim.start = times[times.count / 2]
            let asTheProjectReadsIt = try ProjectCompiler.importData(at: file, settings: settings)
            let trimmedCount = try #require(asTheProjectReadsIt[.speed]).times.count
            #expect(trimmedCount < times.count)

            // Coaching and Replay open the entry's session.
            let forCoaching = try #require(LogbookReferences.load(entry))
            let coachingTimes = try #require(forCoaching[.speed]).times
            #expect(coachingTimes == times, "the project's trim is the project's alone")
            #expect(forCoaching.laps == asTheLogbookReadIt.laps)
        }

        // One reading, and every reader after the first answered from memory.
        #expect(cache.timesRead(file, importerID: id) == 1)
        #expect(cache.counts.reads == 1 && cache.counts.hits >= 3)
    }
}
