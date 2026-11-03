import Foundation
import Importers
import TelemetryKit
import Testing

@testable import ProjectModel

@Suite("Logbook (#345)")
struct LogbookTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    func temporaryLogbook() throws -> Logbook {
        let folder = FileManager.default.temporaryDirectory.appending(path: "logbook-\(UUID().uuidString)")
        return Logbook(directory: folder)
    }

    func entry() throws -> LogbookEntry {
        let session = try RaceRenderCSVImporter().importSession(at: Self.fixture, options: SessionBuilder.Options())
        return try LogbookEntry.make(
            session: session, file: Self.fixture, importerID: "racerender-csv", circuitID: nil, car: "Miata")
    }

    @Test func anEntryIsMadeFromASession() throws {
        let entry = try entry()
        #expect(entry.laps.count == 4)
        #expect(entry.completeLapCount == 4)
        #expect(entry.bestLapNumber == 4)
        #expect(abs((entry.bestLap ?? 0) - 41.2) < 0.05)
        #expect(entry.fastestRollingLap != nil)
        #expect((entry.fastestRollingLap ?? .infinity) <= (entry.bestLap ?? 0) + 0.01)
        #expect(entry.topSpeed ?? 0 > 30)
        #expect(entry.car == "Miata")
        #expect(entry.file.importerID == "racerender-csv")
        #expect(entry.file.contentHash.count == 64)
        #expect(entry.file.byteCount > 1000)
        #expect(entry.title == "coaching-laps", "no circuit and no track name in the fixture: the file's name")
        #expect(entry.resolveFile() == Self.fixture)
        // The hash is of the bytes, so it is stable.
        #expect(try LogbookEntry.hash(of: Self.fixture).hex == entry.file.contentHash)
    }

    @Test func entriesAreSavedOneFileEachAndFoundByHash() throws {
        let logbook = try temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        #expect(logbook.entries().isEmpty)
        var first = try entry()
        first.date = Date(timeIntervalSince1970: 1_700_000_000)
        first.notes = "Cold morning."
        first.tags = ["sprint"]
        first.projects = [.init(path: "/tmp/a.onboardproj", name: "a")]
        try logbook.save(first)
        var second = try entry()
        second.id = UUID()
        second.date = Date(timeIntervalSince1970: 1_800_000_000)
        try logbook.save(second)
        let listed = logbook.entries()
        #expect(listed.map(\.id) == [second.id, first.id], "newest session first")
        let back = try #require(logbook.entry(id: first.id))
        #expect(back.notes == "Cold morning." && back.tags == ["sprint"] && back.projects == first.projects)
        #expect(back.laps == first.laps && back.bestLap == first.bestLap && back.file == first.file)
        #expect(back.date == first.date)
        #expect(back.year == 2023)
        #expect(logbook.entry(forContentHash: first.file.contentHash)?.id != nil)
        #expect(logbook.entry(forContentHash: "nope") == nil)
        try logbook.remove(id: first.id)
        #expect(logbook.entries().count == 1)
        #expect(logbook.url(for: second.id).pathExtension == "onboardsession")
    }

    @Test func theGarageRoundTripsAndOlderEntriesDecode() throws {
        let logbook = try temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        #expect(logbook.cars().isEmpty)
        let cars = [Car(name: "Miata", notes: "NB, 2001"), Car(name: "GR86")]
        try logbook.saveCars(cars)
        #expect(logbook.cars() == cars)
        // An entry file from a future or past build with only the file in it still reads.
        let minimal = """
            { "file": { "path": "/tmp/s.csv", "contentHash": "abc", "byteCount": 1, "importerID": "x" } }
            """
        let older = try Logbook.decoder.decode(LogbookEntry.self, from: Data(minimal.utf8))
        #expect(older.laps.isEmpty && older.car.isEmpty && older.projects.isEmpty)
        #expect(older.title == "s")
        #expect(older.resolveFile() == nil)
    }
}
