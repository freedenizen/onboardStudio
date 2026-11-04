import Foundation
import Testing

@testable import ProjectModel

@Suite("Logbook export and import (#350)")
struct LogbookTransferTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    func scratch(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appending(path: "\(name)-\(UUID().uuidString)")
    }

    func entry(hash: String, date: Date, notes: String = "") -> LogbookEntry {
        LogbookEntry(
            file: .init(path: Self.fixture.path, contentHash: hash, byteCount: 10, importerID: "racerender-csv"),
            trackName: "Stadium", date: date, car: "Miata", driver: "Me",
            laps: [
                .init(number: 1, seconds: 44.6, isComplete: true), .init(number: 2, seconds: nil, isComplete: false),
            ],
            bestLap: 44.6, bestLapNumber: 1, notes: notes,
            conditions: SessionConditions(weather: .sunny, tyres: "RE, 2 days"),
            modified: date)
    }

    @Test func aFolderRoundTripsAndMergesByHash() throws {
        let source = Logbook(directory: scratch("source"))
        let folder = scratch("export")
        let target = Logbook(directory: scratch("target"))
        defer {
            for url in [source.directory, folder, target.directory] { try? FileManager.default.removeItem(at: url) }
        }
        let old = Date(timeIntervalSince1970: 1_700_000_000)
        try source.save(entry(hash: "aaa", date: old))
        try source.save(entry(hash: "bbb", date: old.addingTimeInterval(86_400)))
        try source.saveCars([Car(name: "Miata")])
        let written = try LogbookTransfer.export(
            source.entries(), cars: source.cars(), to: folder, includingFiles: true)
        #expect(written.written == 2 && written.filesCopied == 2, "a copy per entry: different bytes, by their hash")
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        #expect(names.filter { $0.hasSuffix(".onboardsession") }.count == 2)
        #expect(names.contains("garage.json") && names.contains("Files"))
        // Into an empty logbook: everything new, the car too, the copied file found beside.
        let first = try LogbookTransfer.import(from: folder, into: target)
        #expect(first.added == 2 && first.skipped == 0 && first.updated == 0)
        #expect(target.entries().count == 2)
        #expect(target.cars().map(\.name) == ["Miata"])
        // Again: nothing changes.
        let again = try LogbookTransfer.import(from: folder, into: target)
        #expect(again.added == 0 && again.skipped == 2)
        #expect(target.entries().count == 2)
        // A newer version of an entry updates the one with the same bytes, keeping its id.
        let keptID = try #require(target.entries().first { $0.file.contentHash == "aaa" }?.id)
        var newer = entry(hash: "aaa", date: old, notes: "Cold.")
        newer.modified = Date().addingTimeInterval(3_600)  // later than the stamp the source gave its copy
        let update = scratch("update")
        defer { try? FileManager.default.removeItem(at: update) }
        try LogbookTransfer.export([newer], to: update)
        let merged = try LogbookTransfer.import(from: update, into: target)
        #expect(merged.updated == 1 && merged.added == 0)
        #expect(target.entry(id: keptID)?.notes == "Cold.")
        #expect(target.entries().count == 2)
    }

    @Test func csvAndMarkdownSayWhatTheLogbookHolds() {
        let entries = [entry(hash: "aaa", date: Date(timeIntervalSince1970: 1_700_000_000), notes: "Cold, \"grippy\"")]
        let sessions = LogbookTransfer.sessionsCSV(entries)
        let lines = sessions.split(separator: "\n")
        #expect(lines.count == 2)
        #expect(
            lines[0].hasPrefix("date,day,circuit,car,driver,laps,best,best_lap,optimal,rolling,top_speed_kmh,weather"))
        #expect(
            lines[1].contains(",,Stadium,Miata,Me,1,44.600,1,,,,sunny,,,\"RE, 2 days\",,\"Cold, \"\"grippy\"\"\",,"))
        let laps = LogbookTransfer.lapsCSV(entries).split(separator: "\n")
        #expect(laps.count == 3)
        #expect(laps[1].hasSuffix(",Stadium,Miata,1,44.600,yes"))
        #expect(laps[2].hasSuffix(",Stadium,Miata,2,,no"))
        let markdown = LogbookTransfer.markdown(entries, title: "Season")
        let header = "# Season\n\n| Date | Circuit | Car | Laps | Best | Optimal | Rolling | Conditions |"
        #expect(markdown.hasPrefix(header))
        #expect(markdown.contains("| Stadium | Miata | 1 | 0:44.60 | — | — | Sunny · RE, 2 days |"))
        #expect(markdown.contains("## Stadium — "))
        #expect(markdown.contains("- Lap 1: 0:44.60 **best**"))
        #expect(markdown.contains("- Lap 2: — (partial)"))
        #expect(markdown.hasSuffix("Cold, \"grippy\"\n"))
    }
}
