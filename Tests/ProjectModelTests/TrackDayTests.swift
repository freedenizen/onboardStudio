import Foundation
import Testing

@testable import ProjectModel

@Suite("Track days (#392)")
struct TrackDayTests {
    static let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/coaching-laps.csv")

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "logbook-\(UUID().uuidString)"))
    }

    func entry(hash: String, date: Date?, circuitID: String? = nil, trackName: String? = nil, car: String = "Miata")
        -> LogbookEntry
    {
        LogbookEntry(
            file: .init(path: Self.fixture.path, contentHash: hash, byteCount: 10, importerID: "racerender-csv"),
            circuitID: circuitID, trackName: trackName, date: date, car: car, driver: "Me",
            laps: [.init(number: 1, seconds: 44.6, isComplete: true)], bestLap: 44.6, bestLapNumber: 1)
    }

    /// 2026-08-23 at 10:15 local time.
    static var morning: Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 8, day: 23, hour: 10, minute: 15))
            ?? .distantPast
    }

    @Test func aDayRoundTripsAndIsNamedByItsCircuit() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var day = TrackDay(date: Self.morning, circuitID: "Q112563", car: "Miata", driver: "Me", notes: "Hot.")
        day.conditions = SessionConditions(weather: .sunny, track: .dry, ambientCelsius: 31)
        day.clips = [
            ClipRecord(
                path: "/Volumes/GoPro/GX010037.MP4", byteCount: 7, fingerprint: "ff", chapterPaths: ["/x/GX020037.MP4"],
                durationSeconds: 1_700, recordedAt: Self.morning, clock: "GoPro GPS clock", hasGPS: true)
        ]
        #expect(day.date == TrackDay.startOfDay(Self.morning), "a day is a day, not a time")
        #expect(day.title == "Sonoma Raceway", "the catalogue names it")
        #expect(day.label.hasSuffix(" · \(day.title)"))
        #expect(day.year == 2026)
        try logbook.saveDay(day)
        let back = try #require(logbook.day(id: day.id))
        #expect(back.notes == "Hot." && back.car == "Miata" && back.conditions.weather == .sunny)
        #expect(back.clips == day.clips && back.clips[0].name == "GX010037.MP4")
        #expect(back.modified.timeIntervalSince(day.modified) > -1, "stamped now, to the second")
        #expect(logbook.url(forDay: day.id).pathExtension == "onboardday")
        let typed = TrackDay(date: Self.morning, trackName: "Thunderhill West")
        #expect(typed.title == "Thunderhill West")
        #expect(TrackDay(date: Self.morning).title == "Track day")
        // A day written by another build, with only its date, still reads.
        let minimal = try Logbook.decoder.decode(
            TrackDay.self, from: Data("{ \"date\": \"2026-08-23T17:15:00Z\", \"matchedBy\": \"later\" }".utf8))
        #expect(minimal.car.isEmpty && minimal.clips.isEmpty && minimal.conditions.isEmpty)
        let clip = try Logbook.decoder.decode(
            ClipRecord.self, from: Data("{ \"path\": \"/a.mp4\", \"matchedBy\": \"telepathy\" }".utf8))
        #expect(clip.matchedBy == nil && clip.fingerprint.isEmpty, "a word a later build added reads as not matched")
    }

    @Test func entriesAreGroupedIntoDaysByDateAndCircuit() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let morning = Self.morning
        try logbook.save(entry(hash: "a", date: morning, circuitID: "Q112563"))
        try logbook.save(entry(hash: "b", date: morning.addingTimeInterval(3 * 3_600), circuitID: "Q112563"))
        try logbook.save(entry(hash: "c", date: morning.addingTimeInterval(2 * 3_600), circuitID: "Q000"))
        try logbook.save(entry(hash: "d", date: morning.addingTimeInterval(7 * 86_400), circuitID: "Q112563"))
        try logbook.save(entry(hash: "e", date: nil, trackName: "Kart track"))
        #expect(logbook.days().isEmpty)
        #expect(try logbook.ensureDays() == 5)
        let days = logbook.days()
        #expect(days.count == 4, "one day at Sonoma with two sessions, the other circuit, the next week, the undated")
        let entries = logbook.entries()
        let sonoma = try #require(days.first { $0.circuitID == "Q112563" && $0.date == TrackDay.startOfDay(morning) })
        #expect(sonoma.car == "Miata" && sonoma.driver == "Me", "a made day takes the entry's car and driver")
        #expect(Set(entries.filter { $0.trackDayID == sonoma.id }.map(\.file.contentHash)) == ["a", "b"])
        #expect(logbook.sessions(of: sonoma).count == 2)
        let kart = try #require(days.first { $0.trackName == "Kart track" })
        #expect(kart.title == "Kart track")
        #expect(entries.first { $0.file.contentHash == "e" }?.trackDayID == kart.id)
        #expect(try logbook.ensureDays() == 0, "again: nothing to place")
        #expect(logbook.days().count == 4)
        // The sidebar's groups: newest first, with their counts, and an empty day still listed.
        // Later than the undated session's day, which is the day it was added: today.
        let empty = TrackDay(date: morning.addingTimeInterval(400 * 86_400), circuitID: "Q112563")
        try logbook.saveDay(empty)
        let groups = LogbookFilter.days(in: logbook.entries(), days: logbook.days())
        #expect(groups.first.map { $0.scope == .day(id: empty.id, title: empty.label) && $0.count < 1 } == true)
        #expect(groups.first { $0.scope == .day(id: sonoma.id, title: sonoma.label) }?.count == 2)
        #expect(LogbookFilter.apply(entries, scope: .day(id: sonoma.id, title: ""), search: "").count == 2)
        // Removing a day with its sessions leaves the rest alone.
        try logbook.removeDay(id: sonoma.id, andSessions: true)
        #expect(logbook.days().count == 4 && logbook.entries().count == 3)
        try logbook.removeDay(id: kart.id)
        #expect(logbook.entries().count == 3, "the sessions stay")
        #expect(try logbook.ensureDays() == 1, "and are put on a day again")
    }

    @Test func aDayTravelsWithItsSessions() throws {
        let source = temporaryLogbook()
        let target = temporaryLogbook()
        let folder = FileManager.default.temporaryDirectory.appending(path: "export-\(UUID().uuidString)")
        defer {
            for url in [source.directory, target.directory, folder] { try? FileManager.default.removeItem(at: url) }
        }
        var day = TrackDay(date: Self.morning, circuitID: "Q112563", notes: "Windy.")
        day.clips = [ClipRecord(path: "/v/GX010001.MP4", bookmark: Data([1, 2]), byteCount: 3, fingerprint: "x")]
        try source.saveDay(day)
        var first = entry(hash: "a", date: Self.morning, circuitID: "Q112563")
        first.trackDayID = day.id
        try source.save(first)
        let other = TrackDay(date: Self.morning, circuitID: "Q000")
        try source.saveDay(other)
        let written = try LogbookTransfer.export(source.entries(), days: source.days(), to: folder)
        #expect(written.days == 1, "only the days the exported sessions belong to")
        let shipped = try Logbook.readDay(from: folder.appending(path: "\(day.id.uuidString).onboardday"))
        #expect(shipped.clips[0].bookmark == nil, "a clip travels by path alone")
        let imported = try LogbookTransfer.import(from: folder, into: target)
        #expect(imported.added == 1 && imported.days == 1)
        #expect(target.day(id: day.id)?.notes == "Windy.")
        #expect(target.entries().first?.trackDayID == day.id)
        #expect(try LogbookTransfer.import(from: folder, into: target).days == 0, "not newer: left alone")
        let csv = LogbookTransfer.sessionsCSV(target.entries(), days: target.days())
        #expect(
            csv.split(separator: "\n")[1].contains(",\"\(day.label)\",Sonoma"),
            "the label holds a comma, so it is quoted")
        // A session arriving without its day is put on one.
        let orphan = FileManager.default.temporaryDirectory.appending(path: "orphan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: orphan) }
        try LogbookTransfer.export([entry(hash: "b", date: Self.morning.addingTimeInterval(86_400))], to: orphan)
        try LogbookTransfer.import(from: orphan, into: target)
        #expect(target.entries().allSatisfy { $0.trackDayID != nil } && target.days().count == 2)
    }

    /// #453: a session took the day's car when it was added and kept that copy whatever the day
    /// said afterwards. A change on the day now reaches the sessions that still have what it had.
    @Test func aDaysCarAndDriverGoToTheSessionsThatTookThem() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var day = TrackDay(date: Self.morning, trackName: "Somewhere", car: "Miata", driver: "Me")
        try logbook.saveDay(day)
        let elsewhere = TrackDay(date: Self.morning.addingTimeInterval(86_400), trackName: "Elsewhere", car: "Miata")
        try logbook.saveDay(elsewhere)
        func session(_ hash: String, car: String, driver: String = "Me", on day: TrackDay) throws -> LogbookEntry {
            var session = entry(hash: hash, date: Self.morning, trackName: "Somewhere", car: car)
            session.driver = driver
            session.trackDayID = day.id
            try logbook.save(session)
            return session
        }
        let took = try session("a", car: "Miata", on: day)
        let ownCar = try session("b", car: "GR86", on: day)
        let ownDriver = try session("c", car: "Miata", driver: "Alex", on: day)
        let otherDay = try session("d", car: "Miata", on: elsewhere)

        // A typo corrected on the day: the sessions that had the day's car have the new one.
        day.car = "MX-5"
        let changed = try logbook.updateDay(day)
        #expect(Set(changed.map(\.id)) == [took.id, ownDriver.id])
        #expect(logbook.entry(id: took.id)?.car == "MX-5")
        #expect(logbook.entry(id: ownDriver.id)?.car == "MX-5")
        #expect(logbook.entry(id: ownCar.id)?.car == "GR86", "a car of its own is kept")
        #expect(logbook.entry(id: otherDay.id)?.car == "Miata", "another day's sessions are not this day's")
        #expect(logbook.day(id: day.id)?.car == "MX-5")

        // The driver the same way, and one who was named on the session stays.
        day.driver = "Sam"
        #expect(try logbook.updateDay(day).count == 2)
        #expect(logbook.entry(id: took.id)?.driver == "Sam")
        #expect(logbook.entry(id: ownCar.id)?.driver == "Sam")
        #expect(logbook.entry(id: ownDriver.id)?.driver == "Alex")

        // Anything else edited on the day — its notes, its conditions — touches no session.
        day.notes = "Hot."
        #expect(try logbook.updateDay(day).isEmpty)
        #expect(logbook.day(id: day.id)?.notes == "Hot.")
    }

    /// A day made by a files-first import has no car, and neither have its sessions: typing one on
    /// the day is typing it on all of them.
    @Test func aCarTypedOnADayWithNoneReachesItsSessions() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var day = TrackDay(date: Self.morning, trackName: "Somewhere")
        try logbook.saveDay(day)
        var first = entry(hash: "a", date: Self.morning, trackName: "Somewhere", car: "")
        first.trackDayID = day.id
        var second = entry(hash: "b", date: Self.morning, trackName: "Somewhere", car: "GR86")
        second.trackDayID = day.id
        try logbook.save(first)
        try logbook.save(second)
        day.car = "Miata"
        #expect(try logbook.updateDay(day).map(\.id) == [first.id])
        #expect(logbook.entry(id: first.id)?.car == "Miata")
        #expect(logbook.entry(id: second.id)?.car == "GR86")
    }

    /// #455: a day made for files from a place the catalogue does not know has no circuit, and
    /// neither have its sessions. Naming it on the day names it on them.
    @Test func aDaysCircuitGoesToTheSessionsThatHadWhatItHad() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var day = TrackDay(date: Self.morning)
        try logbook.saveDay(day)
        func session(_ hash: String, circuitID: String? = nil, trackName: String? = nil) throws -> LogbookEntry {
            var session = entry(hash: hash, date: Self.morning, circuitID: circuitID, trackName: trackName)
            session.trackDayID = day.id
            try logbook.save(session)
            return session
        }
        let nameless = try session("a")
        let ownName = try session("b", trackName: "Kart Track")
        let recognised = try session("c", circuitID: "Q112563")

        // Named as typed: the session with no circuit takes it; the two that say where they were do not.
        day.trackName = "Stadium"
        #expect(try logbook.updateDay(day).map(\.id) == [nameless.id])
        #expect(logbook.entry(id: nameless.id).map(LogbookFilter.circuitKey(of:)) == "Stadium")
        #expect(logbook.entry(id: ownName.id)?.trackName == "Kart Track")
        #expect(logbook.entry(id: recognised.id)?.circuitID == "Q112563")

        // The spelling corrected on the day follows to the session that took the day's.
        day.trackName = "The Stadium"
        #expect(try logbook.updateDay(day).map(\.id) == [nameless.id])
        #expect(logbook.entry(id: nameless.id)?.trackName == "The Stadium")

        // Found in the catalogue after all: the session is at that circuit, by its id.
        day.circuitID = "Q1140156"
        day.trackName = nil
        #expect(try logbook.updateDay(day).map(\.id) == [nameless.id])
        #expect(logbook.entry(id: nameless.id)?.circuitID == "Q1140156")
        #expect(logbook.entry(id: recognised.id)?.circuitID == "Q112563", "its trace says where it was")
    }

    /// A file with no date of its own goes on the day its file is dated, not the day it was added.
    @Test func anUndatedSessionGoesOnTheDayItsFileIsDated() throws {
        let logbook = temporaryLogbook()
        let folder = FileManager.default.temporaryDirectory.appending(path: "undated-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: logbook.directory)
            try? FileManager.default.removeItem(at: folder)
        }
        let file = folder.appending(path: "log.csv")
        try Data("x".utf8).write(to: file)
        try FileManager.default.setAttributes(
            [.creationDate: Self.morning, .modificationDate: Self.morning.addingTimeInterval(3_600)],
            ofItemAtPath: file.path)
        var undated = LogbookEntry(file: .init(path: file.path, contentHash: "u", byteCount: 1, importerID: "x"))
        undated.added = Self.morning.addingTimeInterval(30 * 86_400)
        #expect(try logbook.day(for: undated).date == TrackDay.startOfDay(Self.morning))

        // A file that is not where the entry says leaves only the day it was added.
        var gone = LogbookEntry(
            file: .init(path: folder.appending(path: "gone.csv").path, contentHash: "g", byteCount: 1, importerID: "x"))
        gone.added = Self.morning.addingTimeInterval(60 * 86_400)
        #expect(try logbook.day(for: gone).date == TrackDay.startOfDay(gone.added))
        // And a file that says when it was driven is believed over its own date.
        var dated = undated
        dated.date = Self.morning.addingTimeInterval(-10 * 86_400)
        #expect(try logbook.day(for: dated).date == TrackDay.startOfDay(try #require(dated.date)))
    }

    /// A session with no circuit of its own is put on the day its date says, and when that day
    /// has a circuit it is at the day's (#455): nothing says it was driven anywhere else.
    @Test func aSessionWithNoCircuitTakesTheCircuitOfTheDayItJoins() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let named = TrackDay(date: Self.morning, trackName: "Stadium")
        try logbook.saveDay(named)

        var nameless = entry(hash: "a", date: Self.morning)
        #expect(try logbook.assignDay(to: &nameless).id == named.id)
        #expect(nameless.trackDayID == named.id && nameless.trackName == "Stadium")

        // One that says where it was goes on a day of its own, and keeps its name.
        var elsewhere = entry(hash: "b", date: Self.morning, trackName: "Kart Track")
        let own = try logbook.assignDay(to: &elsewhere)
        #expect(own.id != named.id && elsewhere.trackName == "Kart Track")

        // A catalogue circuit on the day is taken by its id.
        let logbookTwo = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbookTwo.directory) }
        let sonoma = TrackDay(date: Self.morning, circuitID: "Q112563")
        try logbookTwo.saveDay(sonoma)
        var noGPS = entry(hash: "c", date: Self.morning)
        try logbookTwo.assignDay(to: &noGPS)
        #expect(noGPS.circuitID == "Q112563" && noGPS.trackDayID == sonoma.id)

        // A day with no circuit lends none.
        let logbookThree = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbookThree.directory) }
        var alone = entry(hash: "d", date: Self.morning)
        try logbookThree.assignDay(to: &alone)
        #expect(LogbookFilter.circuitKey(of: alone).isEmpty)
    }
}
