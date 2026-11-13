import Foundation
import Testing

@testable import ProjectModel

@Suite("The garage (#489, #490)")
struct GarageTests {
    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "garage-\(UUID().uuidString)"))
    }

    static func date(_ month: Int, _ day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 11)) ?? .distantPast
    }

    static func entry(
        _ hash: String, car: String, day: TrackDay? = nil, track: String = "Stadium", on date: Date? = nil
    ) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"),
            trackName: track, date: date ?? day?.date ?? Self.date(9, 1), car: car, trackDayID: day?.id)
    }

    @Test func aCarIsSummedUpBySessionsDaysAndCircuits() {
        let spring = TrackDay(date: Self.date(3, 14), trackName: "Stadium", car: "Miata")
        let autumn = TrackDay(date: Self.date(11, 8), trackName: "Hilltop", car: "Miata")
        let begun = TrackDay(date: Self.date(12, 1), trackName: "Coast", car: "Miata")
        let entries = [
            Self.entry("a", car: "Miata", day: spring), Self.entry("b", car: "Miata", day: spring),
            Self.entry("c", car: " Miata ", day: autumn, track: "Hilltop"), Self.entry("d", car: "GR86", day: autumn),
        ]
        let summary = Garage.summary(of: "Miata", entries: entries, days: [spring, autumn, begun])
        #expect(summary.sessions == 3)
        // The day begun with no sessions yet names the car too.
        #expect(summary.days == 3)
        #expect(summary.circuits == 3)
        #expect(summary.first == spring.date && summary.last == begun.date)
        #expect(!summary.isUnused)
        #expect(Garage.summary(of: "Typo", entries: entries, days: [spring]).isUnused)
    }

    @Test func theDaysAnImportLeftWithNoCarAreTheOnesItsSessionsWentOnto() {
        let first = TrackDay(date: Self.date(9, 20), trackName: "Stadium")
        let second = TrackDay(date: Self.date(10, 12), trackName: "Stadium")
        let named = TrackDay(date: Self.date(11, 8), trackName: "Stadium", car: "Miata")
        let older = TrackDay(date: Self.date(8, 1), trackName: "Stadium")
        let entries = [
            Self.entry("a", car: "", day: second), Self.entry("b", car: "", day: first),
            Self.entry("c", car: "", day: named), Self.entry("d", car: "", day: older),
        ]
        let added = Set(entries.prefix(3).map(\.id))
        let days = Garage.daysWithoutCar(added: added, entries: entries, days: [named, second, first, older])
        // Oldest first; a day that names a car, and one nothing new went onto, are not asked about.
        #expect(days.map(\.id) == [first.id, second.id])
        // A new session that took a car from an earlier one leaves its day alone.
        let given = [Self.entry("e", car: "GR86", day: first)]
        #expect(Garage.daysWithoutCar(added: Set(given.map(\.id)), entries: given, days: [first]).isEmpty)
    }

    @Test func aCarSetOnTheDaysFillsTheirSessionsAndJoinsTheGarage() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let first = TrackDay(date: Self.date(9, 20), trackName: "Stadium")
        let second = TrackDay(date: Self.date(10, 12), trackName: "Stadium")
        try logbook.saveDay(first)
        try logbook.saveDay(second)
        let own = Self.entry("b", car: "GR86", day: second)
        for entry in [Self.entry("a", car: "", day: first), own, Self.entry("c", car: "", day: second)] {
            try logbook.save(entry)
        }
        try logbook.setCar(" Miata ", onDays: [first.id, second.id])
        #expect(logbook.days().map(\.car) == ["Miata", "Miata"])
        let cars = Dictionary(uniqueKeysWithValues: logbook.entries().map { ($0.file.contentHash, $0.car) })
        // A session given a car of its own keeps it.
        #expect(cars == ["a": "Miata", "b": "GR86", "c": "Miata"])
        #expect(logbook.cars().map(\.name) == ["Miata"])
    }

    @Test func aRenameReachesEveryDayAndSessionAndKeepsTheNotes() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = TrackDay(date: Self.date(9, 20), trackName: "Stadium", car: "Mitaa")
        try logbook.saveDay(day)
        try logbook.save(Self.entry("a", car: "Mitaa", day: day))
        try logbook.save(Self.entry("b", car: "GR86", day: day))
        try logbook.saveCars([Car(name: "Mitaa", notes: "Soft springs"), Car(name: "GR86")])
        #expect(try logbook.renameCar("Mitaa", to: " Miata") == "Miata")
        #expect(logbook.days().map(\.car) == ["Miata"])
        #expect(Set(logbook.entries().map(\.car)) == ["Miata", "GR86"])
        #expect(
            logbook.cars() == [Car(id: logbook.cars()[0].id, name: "Miata", notes: "Soft springs"), logbook.cars()[1]])
        // Only the case: the same car, renamed.
        #expect(try logbook.renameCar("Miata", to: "MIATA") == "MIATA")
        #expect(logbook.cars().map(\.name) == ["MIATA", "GR86"])
    }

    @Test func aRenameToAnotherCarsNameMakesTheTwoOne() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        try logbook.save(Self.entry("a", car: "Miata"))
        try logbook.save(Self.entry("b", car: "Mitaa"))
        try logbook.saveCars([Car(name: "Miata", notes: "Soft springs"), Car(name: "Mitaa", notes: "New pads")])
        // Typed in another case: the car the logbook has keeps its spelling.
        #expect(try logbook.renameCar("Mitaa", to: "miata") == "Miata")
        #expect(logbook.entries().map(\.car) == ["Miata", "Miata"])
        let cars = logbook.cars()
        #expect(cars.map(\.name) == ["Miata"])
        #expect(cars.first?.notes == "Soft springs\n\nNew pads")
        #expect(LogbookFilter.cars(in: logbook.entries(), garage: cars).map(\.count) == [2])
    }

    @Test func onlyACarNothingNamesIsTakenOutOfTheGarage() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = TrackDay(date: Self.date(12, 1), trackName: "Coast", car: "Begun")
        try logbook.saveDay(day)
        try logbook.save(Self.entry("a", car: "miata"))
        try logbook.saveCars([Car(name: "Miata"), Car(name: "Begun"), Car(name: "Typo", notes: "x")])
        #expect(try !logbook.removeCar(named: "Miata"), "a session names it, in another case")
        #expect(try !logbook.removeCar(named: "Begun"), "a day with no sessions yet names it")
        #expect(try logbook.removeCar(named: "Typo"))
        #expect(try !logbook.removeCar(named: "Typo"), "already gone")
        #expect(logbook.cars().map(\.name) == ["Miata", "Begun"])
    }

    @Test func aNamePutRightLeavesTheGarageUnlessItHasNotes() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = TrackDay(date: Self.date(12, 1), trackName: "Coast", car: "Begun")
        try logbook.saveDay(day)
        try logbook.save(Self.entry("a", car: "miata"))
        try logbook.saveCars([
            Car(name: "Miata"), Car(name: "Begun"), Car(name: "Tset"), Car(name: "Sold", notes: "Went in May"),
        ])
        #expect(try logbook.tidyGarage())
        // Named in another case, named on a day, or with notes: kept. The bare typo is not.
        #expect(logbook.cars().map(\.name) == ["Miata", "Begun", "Sold"])
        #expect(try !logbook.tidyGarage(), "nothing more to take out")
    }

    @Test func notesAreKeptWithTheCar() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        try logbook.save(Self.entry("a", car: "Miata"))
        // Named only on a session until now: it joins the garage with its notes.
        try logbook.saveNotes("  Soft springs\n", forCar: "miata")
        #expect(logbook.cars().map(\.name) == ["miata"])
        #expect(logbook.cars().first?.notes == "Soft springs")
        try logbook.saveNotes("Stiffer springs", forCar: "Miata")
        #expect(logbook.cars().count == 1)
        #expect(logbook.cars().first?.notes == "Stiffer springs")
        try logbook.addToGarage("MIATA")
        #expect(logbook.cars().count == 1, "the same car in another case")
    }

    @Test func theSidebarAndTheCarFieldsOfferTheGaragesUnnamedCarsLast() {
        let entries = [Self.entry("a", car: "Miata"), Self.entry("b", car: "Miata"), Self.entry("c", car: "")]
        let garage = [Car(name: "miata"), Car(name: "Typo"), Car(name: "Barchetta")]
        let groups = LogbookFilter.cars(in: entries, garage: garage)
        #expect(groups.map(\.scope.title) == ["Miata", "Barchetta", "Typo", "No car"])
        #expect(groups.map(\.count) == [2, 0, 0, 1])
        let days = [TrackDay(date: Self.date(12, 1), car: "GR86")]
        #expect(
            LogbookFilter.knownCars(in: entries, days: days, garage: garage) == ["Miata", "GR86", "Barchetta", "Typo"])
        #expect(LogbookFilter.cars(in: entries).count == 2, "without the garage, as before")
    }
}
