import Foundation
import Testing

@testable import ProjectModel

/// Correcting the date of a track day (#654).
@Suite("A track day's date (#654)")
struct TrackDayDateTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    /// 2026-08-23 at 10:15 local time.
    static var morning: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 10, minute: 15))
            ?? .distantPast
    }

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "logbook-\(UUID().uuidString)"))
    }

    func entry(hash: String, date: Date?, trackName: String) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: Self.fixture.path, contentHash: hash, byteCount: 10, importerID: "racerender-csv"),
            trackName: trackName, date: date, car: "Miata", driver: "Me",
            laps: [.init(number: 1, seconds: 44.6, isComplete: true)], bestLap: 44.6, bestLapNumber: 1)
    }

    /// #654: a day's date can be corrected. Its sessions keep the dates their own files gave
    /// them; one with no date of its own is counted on the day's new date.
    @Test func aDaysDateCanBeCorrectedAndItsSessionsKeepTheirOwn() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var day = TrackDay(date: Self.morning, trackName: "Stadium", car: "Miata", driver: "Me")
        try logbook.saveDay(day)
        var dated = entry(hash: "dated", date: Self.morning, trackName: "Stadium")
        dated.trackDayID = day.id
        try logbook.save(dated)
        var undated = entry(hash: "undated", date: nil, trackName: "Stadium")
        undated.trackDayID = day.id
        try logbook.save(undated)

        let before = day
        let week = Self.morning.addingTimeInterval(7 * 86_400)
        day.date = TrackDay.startOfDay(week)
        #expect(LogbookEditName.of(before, day) == "Change Date")
        let carried = try logbook.updateDay(day)
        #expect(carried.isEmpty, "a date is the day's own: no session is rewritten for it")

        let kept = try #require(logbook.day(id: day.id))
        #expect(kept.date == TrackDay.startOfDay(week))
        #expect(kept.label.hasPrefix(week.formatted(date: .abbreviated, time: .omitted)))
        let entries = logbook.entries()
        #expect(entries.first { $0.id == dated.id }?.date == Self.morning, "its file's date stands")
        let floating = try #require(entries.first { $0.id == undated.id })
        #expect(floating.date == nil)
        #expect(floating.when == TrackDay.startOfDay(week), "with no date of its own it is counted on the day's")
    }
}
