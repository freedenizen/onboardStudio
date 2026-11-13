import Foundation
import Testing

@testable import ProjectModel

@Suite("Correcting the logbook (#454)")
struct LogbookCorrectionsTests {
    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "corrections-\(UUID().uuidString)"))
    }

    static func date(_ month: Int, _ day: Int, hour: Int = 11) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: day, hour: hour))
            ?? .distantPast
    }

    static func entry(
        _ hash: String, day: TrackDay?, car: String = "", track: String? = nil, circuitID: String? = nil,
        on date: Date? = nil
    ) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"),
            circuitID: circuitID, trackName: track, date: date ?? day?.date ?? Self.date(9, 1), car: car,
            trackDayID: day?.id)
    }

    static func clip(_ path: String, of entry: LogbookEntry?) -> ClipRecord {
        ClipRecord(path: path, byteCount: 1, fingerprint: path, sessionID: entry?.id)
    }

    @Test func anEditIsTakenBackAndDoneAgainWithoutTouchingWhatOthersWrote() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = TrackDay(date: Self.date(9, 20), trackName: "Stadium", car: "Miata")
        try logbook.saveDay(day)
        let kept = Self.entry("a", day: day, car: "Miata")
        let removed = Self.entry("b", day: day, car: "Miata")
        try logbook.save(kept)
        try logbook.save(removed)
        try logbook.saveCars([Car(name: "Miata")])

        let before = logbook.snapshot()
        try logbook.remove(id: removed.id)
        try logbook.renameCar("Miata", to: "MX-5")
        let change = LogbookChange(from: before, to: logbook.snapshot())
        #expect(change.entries.keys.sorted() == [kept.id, removed.id].sorted())
        #expect(change.days.keys.sorted() == [day.id])
        #expect(change.garage != nil)

        // Written since by something else: Undo leaves it.
        var other = Self.entry("c", day: day)
        other.notes = "From the Coaching window"
        try logbook.save(other)

        try logbook.apply(change.reversed)
        let undone = Dictionary(uniqueKeysWithValues: logbook.entries().map { ($0.id, $0) })
        #expect(
            undone[removed.id] == before.entries.first { $0.id == removed.id },
            "the session is back as it was, its modified date too")
        #expect(undone[kept.id]?.car == "Miata")
        #expect(undone[other.id]?.notes == "From the Coaching window")
        #expect(logbook.day(id: day.id)?.car == "Miata")
        #expect(logbook.cars().map(\.name) == ["Miata"])

        try logbook.apply(change)
        #expect(logbook.entry(id: removed.id) == nil)
        #expect(logbook.day(id: day.id)?.car == "MX-5")
        #expect(logbook.entries().count == 2)
    }

    @Test func aDayAndItsSessionsComeBackTogether() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = TrackDay(date: Self.date(9, 20), trackName: "Stadium")
        try logbook.saveDay(day)
        try logbook.save(Self.entry("a", day: day))
        try logbook.save(Self.entry("b", day: day))
        let before = logbook.snapshot()
        try logbook.removeDay(id: day.id, andSessions: true)
        let change = LogbookChange(from: before, to: logbook.snapshot())
        #expect(change.entries.values.allSatisfy { $0.after == nil })
        try logbook.apply(change.reversed)
        #expect(logbook.days() == before.days)
        #expect(logbook.sessions(of: day).count == 2)
        #expect(LogbookChange(from: before, to: logbook.snapshot()).isEmpty)
    }

    @Test func aSessionMovesWithItsClipsAndTakesWhatItHadFromItsDay() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var wrong = TrackDay(date: Self.date(9, 20), trackName: "Stadium", car: "Miata")
        var right = TrackDay(date: Self.date(9, 21), trackName: "Hilltop", car: "GR86")
        right.driver = "Sam"
        let followed = Self.entry("a", day: wrong, car: "Miata", track: "Stadium")
        let own = Self.entry("b", day: wrong, car: "Loan Car", circuitID: "Q1", on: Self.date(9, 21))
        let stays = Self.entry("c", day: wrong, car: "Miata", track: "Stadium")
        wrong.clips = [
            Self.clip("/v/1.mp4", of: followed), Self.clip("/v/2.mp4", of: stays),
        ]
        try logbook.saveDay(wrong)
        try logbook.saveDay(right)
        for entry in [followed, own, stays] { try logbook.save(entry) }

        #expect(try logbook.move([followed.id, own.id, right.id], toDay: right.id) == 2)
        let moved = Dictionary(uniqueKeysWithValues: logbook.entries().map { ($0.file.contentHash, $0) })
        #expect(moved["a"]?.trackDayID == right.id && moved["b"]?.trackDayID == right.id)
        #expect(moved["c"]?.trackDayID == wrong.id)
        // The day's car and driver, the day's typed circuit: what it had from the day it left.
        #expect(moved["a"]?.car == "GR86" && moved["a"]?.driver == "Sam")
        #expect(moved["a"]?.trackName == "Hilltop")
        // Its own car and recognised circuit go with it.
        #expect(moved["b"]?.car == "Loan Car" && moved["b"]?.circuitID == "Q1")
        #expect(logbook.day(id: right.id)?.clips.map(\.path) == ["/v/1.mp4"])
        #expect(logbook.day(id: wrong.id)?.clips.map(\.path) == ["/v/2.mp4"])
        #expect(try logbook.move([followed.id], toDay: right.id) == 0, "already there")
    }

    @Test func aSessionGoesBackToTheDayItsOwnDateSays() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let chosen = TrackDay(date: Self.date(9, 20), trackName: "Stadium")
        try logbook.saveDay(chosen)
        // Added to the chosen day though its clock said the 21st.
        let entry = Self.entry("a", day: chosen, track: "Stadium", on: Self.date(9, 21))
        try logbook.save(entry)
        #expect(try logbook.moveToOwnDays([entry.id]) == 1)
        let day = try #require(logbook.entry(id: entry.id)?.trackDayID.flatMap { logbook.day(id: $0) })
        #expect(day.date == TrackDay.startOfDay(Self.date(9, 21)))
        #expect(day.trackName == "Stadium")
        #expect(try logbook.moveToOwnDays([entry.id]) == 0, "it is on its own day")
    }

    @Test func anEditIsNamedForWhatItChanged() {
        let day = TrackDay(date: Self.date(9, 20), trackName: "Stadium")
        let entry = Self.entry("a", day: day)
        var car = entry
        car.car = "Miata"
        #expect(LogbookEditName.of(entry, car) == "Change Car")
        var notes = entry
        notes.notes = "Wet"
        #expect(LogbookEditName.of(entry, notes) == "Change Notes")
        var both = car
        both.driver = "Sam"
        #expect(LogbookEditName.of(entry, both) == "Change Session")
        var circuit = day
        circuit.trackName = "Hilltop"
        #expect(LogbookEditName.of(day, circuit) == "Change Circuit")
        var clip = day
        clip.clips = [Self.clip("/v/1.mp4", of: nil)]
        var assigned = clip
        assigned.clips[0].sessionID = entry.id
        #expect(LogbookEditName.of(clip, assigned) == "Assign Clip")
        #expect(LogbookEditName.removing(1) == "Remove Session")
        #expect(LogbookEditName.moving(3) == "Move 3 Sessions")
    }
}
