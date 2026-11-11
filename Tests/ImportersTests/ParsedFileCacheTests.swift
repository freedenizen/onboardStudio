import Foundation
import Testing

@testable import Importers
@testable import TelemetryKit

/// #482: a data file was read from scratch by everything that opened it — the Logbook's import, a
/// project, Coaching — though reading is nearly all parsing and the parsed table is the same for
/// all of them. The table is now kept for the file as it was, and each reader builds its own
/// session from it.
@Suite("A file is read once (#482)")
struct ParsedFileCacheTests {
    /// Counts how often it is asked to read, and gives a table of `rows` rows.
    final class Reader: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0
        var reads: Int { lock.withLock { count } }

        func table(rows: Int = 3, columns: Int = 2) -> RawTable {
            lock.withLock { count += 1 }
            let times = (0..<rows).map(Double.init)
            let column = RawColumn(name: "speed", unit: .metersPerSecond, values: times.map { Optional($0 * 2) })
            return RawTable(
                info: SessionInfo(sourceFormat: "test"), times: times,
                columns: Array(repeating: column, count: columns))
        }
    }

    /// A clock the test moves by hand.
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var date = Date(timeIntervalSince1970: 1_800_000_000)
        var now: Date { lock.withLock { date } }
        func advance(_ seconds: Double) { lock.withLock { date = date.addingTimeInterval(seconds) } }
    }

    func temporaryFile(_ text: String = "one\n") throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "parsed-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: "session.csv")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func aFileIsReadOnceHoweverOftenItIsAskedFor() throws {
        let cache = ParsedFileCache()
        let reader = Reader()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = cache.table(at: url, importerID: "test") { reader.table() }
        let second = cache.table(at: url, importerID: "test") { reader.table() }
        let third = cache.table(at: url, importerID: "test") { reader.table() }
        #expect(reader.reads == 1)
        #expect(first.times == second.times && second.times == third.times)
        #expect(cache.counts == ParsedFileCache.Counts(hits: 2, reads: 1))
        #expect(cache.timesRead(url, importerID: "test") == 1)
        // By another spelling of the same path, too.
        let spelled = url.deletingLastPathComponent().appending(path: "./session.csv")
        _ = cache.table(at: spelled, importerID: "test") { reader.table() }
        #expect(reader.reads == 1)
    }

    @Test func aFileThatChangedIsReadAgain() throws {
        let cache = ParsedFileCache()
        let reader = Reader()
        let url = try temporaryFile("one\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = cache.table(at: url, importerID: "test") { reader.table(rows: 3) }
        // Edited in place: longer, and dated later.
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("two\n".utf8))
        try handle.close()
        let after = cache.table(at: url, importerID: "test") { reader.table(rows: 4) }
        #expect(reader.reads == 2 && after.rowCount == 4)
        #expect(cache.timesRead(url, importerID: "test") == 2)
        // And once more it is the new table that is kept.
        #expect(cache.table(at: url, importerID: "test") { reader.table(rows: 9) }.rowCount == 4)
        #expect(reader.reads == 2)
    }

    @Test func aFileReplacedByAnotherOfTheSameSizeAndDateIsReadAgain() throws {
        let cache = ParsedFileCache()
        let reader = Reader()
        let url = try temporaryFile("aaaa\n")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let dated = try #require(try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        _ = cache.table(at: url, importerID: "test") { reader.table(rows: 3) }
        // Another file saved over it — a new file under the old name — with the same length, and
        // its date put back to the old one: only what the file *is* on the volume tells them apart.
        try "bbbb\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: dated], ofItemAtPath: url.path)
        let after = cache.table(at: url, importerID: "test") { reader.table(rows: 5) }
        #expect(reader.reads == 2 && after.rowCount == 5)
    }

    @Test func eachImporterKeepsItsOwnReading() throws {
        let cache = ParsedFileCache()
        let reader = Reader()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(cache.table(at: url, importerID: "generic-csv") { reader.table(rows: 3) }.rowCount == 3)
        #expect(cache.table(at: url, importerID: "racechrono-csv") { reader.table(rows: 7) }.rowCount == 7)
        #expect(cache.table(at: url, importerID: "generic-csv") { reader.table(rows: 1) }.rowCount == 3)
        #expect(reader.reads == 2)
    }

    @Test func aReadThatFailsKeepsNothing() throws {
        let cache = ParsedFileCache()
        let reader = Reader()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        #expect(throws: ImportError.noData) {
            try cache.table(at: url, importerID: "test") { throw ImportError.noData }
        }
        #expect(cache.kept.files == 0)
        #expect(cache.table(at: url, importerID: "test") { reader.table() }.rowCount == 3)
        #expect(reader.reads == 1)
    }

    @Test func aFileThatIsNotThereIsReadAndNotKept() {
        let cache = ParsedFileCache()
        let reader = Reader()
        let nowhere = URL(fileURLWithPath: "/nowhere/\(UUID().uuidString).csv")
        _ = cache.table(at: nowhere, importerID: "test") { reader.table() }
        _ = cache.table(at: nowhere, importerID: "test") { reader.table() }
        #expect(reader.reads == 2 && cache.kept.files == 0)
    }

    @Test func theLeastRecentlyUsedGoesFirstPastTheBudget() throws {
        let clock = Clock()
        let cache = ParsedFileCache(limits: .init(files: 2), now: { clock.now })
        let reader = Reader()
        let urls = try (0..<3).map { _ in try temporaryFile() }
        defer { for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
        _ = cache.table(at: urls[0], importerID: "test") { reader.table() }
        clock.advance(1)
        _ = cache.table(at: urls[1], importerID: "test") { reader.table() }
        clock.advance(1)
        // The first is asked for again, so the second is now the one longest unused.
        _ = cache.table(at: urls[0], importerID: "test") { reader.table() }
        clock.advance(1)
        _ = cache.table(at: urls[2], importerID: "test") { reader.table() }
        #expect(cache.kept.files == 2)
        #expect(cache.timesRead(urls[0], importerID: "test") == 1 && cache.timesRead(urls[2], importerID: "test") == 1)
        #expect(cache.timesRead(urls[1], importerID: "test") == 0)
        #expect(reader.reads == 3)
    }

    @Test func theBudgetIsInBytesAndATableOverItIsNotKept() throws {
        // 100 rows of two columns: 100 × (8 + 2 × 16) bytes.
        let reader = Reader()
        #expect(ParsedFileCache.cost(of: reader.table(rows: 100, columns: 2)) == 4_000)
        let clock = Clock()
        let cache = ParsedFileCache(limits: .init(bytes: 10_000), now: { clock.now })
        let urls = try (0..<4).map { _ in try temporaryFile() }
        defer { for url in urls { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) } }
        for url in urls.prefix(3) {
            _ = cache.table(at: url, importerID: "test") { reader.table(rows: 100, columns: 2) }
            clock.advance(1)
        }
        // Three would be 12,000: the first read went to make room.
        #expect(cache.kept.files == 2 && cache.kept.bytes == 8_000)
        #expect(cache.timesRead(urls[0], importerID: "test") == 0)
        // One table bigger than the whole budget is handed over and not kept; the others stay.
        let big = cache.table(at: urls[3], importerID: "test") { reader.table(rows: 1_000, columns: 2) }
        #expect(big.rowCount == 1_000)
        #expect(cache.kept.files == 2 && cache.timesRead(urls[3], importerID: "test") == 0)
    }

    @Test func aTableNobodyAsksForIsDropped() throws {
        let clock = Clock()
        let cache = ParsedFileCache(limits: .init(idleSeconds: 600), now: { clock.now })
        let reader = Reader()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = cache.table(at: url, importerID: "test") { reader.table() }
        clock.advance(500)
        // Asked for within the time, it is kept, and the time runs from now.
        _ = cache.table(at: url, importerID: "test") { reader.table() }
        clock.advance(500)
        cache.dropIdle()
        #expect(cache.kept.files == 1 && reader.reads == 1)
        clock.advance(601)
        cache.dropIdle()
        #expect(cache.kept.files == 0)
        _ = cache.table(at: url, importerID: "test") { reader.table() }
        #expect(reader.reads == 2)
    }

    @Test func removingEverythingMakesTheNextReaderRead() throws {
        let cache = ParsedFileCache()
        let reader = Reader()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = cache.table(at: url, importerID: "test") { reader.table() }
        cache.removeAll()
        #expect(cache.kept.files == 0)
        _ = cache.table(at: url, importerID: "test") { reader.table() }
        #expect(reader.reads == 2)
    }

    @Test func readersThatArriveTogetherReadTheFileOnce() throws {
        let cache = ParsedFileCache()
        let reader = Reader()
        let url = try temporaryFile()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        DispatchQueue.concurrentPerform(iterations: 12) { _ in
            let table = cache.table(at: url, importerID: "test") {
                // Long enough that the others arrive while this one is still reading.
                Thread.sleep(forTimeInterval: 0.05)
                return reader.table()
            }
            #expect(table.rowCount == 3)
        }
        #expect(reader.reads == 1)
        #expect(cache.counts == ParsedFileCache.Counts(hits: 11, reads: 1))
    }
}

/// The same through the importers, which is how every reader in the app comes to a file.
@Suite("Importers share one reading of a file (#482)")
struct SharedReadingTests {
    func copy(of fixture: String) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "shared-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fixture)
        try FileManager.default.copyItem(at: try Fixtures.url(fixture), to: url)
        return url
    }

    @Test func twoReadersWithDifferentSettingsShareTheReadingAndNothingElse() throws {
        let url = try copy(of: "racechrono-v3.csv")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let importer = RaceChronoCSVImporter()
        let id = RaceChronoCSVImporter.id
        // As the Logbook reads it, then as a project that trims the first half off reads it.
        let whole = try importer.importSession(at: url)
        var options = SessionBuilder.Options()
        let raw = try importer.importFile(at: url)
        options.trimStart = raw.times[raw.times.count / 2]
        let trimmed = try importer.importSession(at: url, options: options)
        #expect(ParsedFileCache.shared.timesRead(url, importerID: id) == 1)
        // The second reader's settings are its own: nothing of the first reader's session came along.
        let wholeCount = try #require(whole[.speed]).times.count
        let trimmedCount = try #require(trimmed[.speed]).times.count
        #expect(trimmedCount < wholeCount)
        // And the first reader, asking again, gets what it got before.
        let again = try importer.importSession(at: url)
        let againTimes = try #require(again[.speed]).times
        let wholeTimes = try #require(whole[.speed]).times
        #expect(againTimes == wholeTimes)
        #expect(again.laps == whole.laps)
        #expect(ParsedFileCache.shared.timesRead(url, importerID: id) == 1)
    }

    @Test func theDetectorsImportSharesItToo() throws {
        let url = try copy(of: "racechrono-v3.csv")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        _ = try FormatDetector.importSession(at: url)
        _ = try FormatDetector.importSession(at: url)
        _ = try RaceChronoCSVImporter().importSession(at: url)
        #expect(ParsedFileCache.shared.timesRead(url, importerID: RaceChronoCSVImporter.id) == 1)
    }

    @Test func aFileEditedBetweenTwoImportsIsReadAgain() throws {
        let url = try copy(of: "racechrono-v3.csv")
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let importer = RaceChronoCSVImporter()
        let before = try importer.importSession(at: url)
        // The last data row goes: the file is shorter and the session ends sooner.
        var lines = try String(contentsOf: url, encoding: .utf8).split(
            separator: "\n", omittingEmptySubsequences: false)
        while lines.last?.isEmpty == true { lines.removeLast() }
        lines.removeLast()
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        let after = try importer.importSession(at: url)
        let beforeCount = try #require(before[.speed]).times.count
        let afterCount = try #require(after[.speed]).times.count
        #expect(afterCount == beforeCount - 1)
    }
}
