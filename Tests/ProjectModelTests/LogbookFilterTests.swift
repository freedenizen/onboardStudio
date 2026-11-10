import Foundation
import Testing

@testable import ProjectModel

@Suite("Logbook filter (#347)")
struct LogbookFilterTests {
    func entry(_ name: String, circuit: String? = nil, track: String? = nil, car: String = "", year: Int? = nil)
        -> LogbookEntry
    {
        var date: Date?
        if let year {
            date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 6, day: 1))
        }
        return LogbookEntry(
            file: .init(path: "/days/\(name).csv", contentHash: name, byteCount: 1, importerID: "x"),
            circuitID: circuit, trackName: track, date: date, car: car, driver: "Me", notes: "", tags: ["sprint"])
    }

    var entries: [LogbookEntry] {
        [
            entry("a", circuit: "Q112563", car: "Miata", year: 2026),
            entry("b", circuit: "Q112563", car: "Miata", year: 2025),
            entry("c", track: "Thunderhill", car: "GR86", year: 2026),
            entry("d", track: "Thunderhill", year: nil),
        ]
    }

    @Test func theSidebarGroupsByCircuitCarAndYear() {
        let circuits = LogbookFilter.circuits(in: entries)
        #expect(circuits.count == 2)
        #expect(circuits[0].count == 2 && circuits[0].scope.title == "Sonoma Raceway")
        #expect(circuits[1].scope == .circuit(id: "Thunderhill", title: "Thunderhill"))
        let cars = LogbookFilter.cars(in: entries)
        #expect(cars.map(\.scope) == [.car("Miata"), .car("GR86"), .car("")])
        #expect(cars.last?.scope.title == "No car")
        #expect(LogbookFilter.years(in: entries).map(\.scope) == [.year(2026), .year(2025)])
    }

    @Test func scopesAndSearchNarrowTheList() {
        let all = entries
        #expect(LogbookFilter.apply(all, scope: .all, search: "").count == 4)
        #expect(LogbookFilter.apply(all, scope: .circuit(id: "Q112563", title: ""), search: "").count == 2)
        #expect(LogbookFilter.apply(all, scope: .car("GR86"), search: "").map(\.file.contentHash) == ["c"])
        #expect(LogbookFilter.apply(all, scope: .year(2026), search: "").count == 2)
        #expect(LogbookFilter.apply(all, scope: .all, search: "sonoma").count == 2)
        #expect(LogbookFilter.apply(all, scope: .all, search: "thunder gr86").map(\.file.contentHash) == ["c"])
        #expect(LogbookFilter.apply(all, scope: .all, search: "SPRINT").count == 4, "tags, any case")
        #expect(LogbookFilter.apply(all, scope: .all, search: "d.csv").count == 1, "the file's name")
        #expect(LogbookFilter.apply(all, scope: .year(2025), search: "gr86").isEmpty)
    }

    /// #453: one list of cars for every Car field — the days' and the sessions', most used first.
    @Test func theKnownCarsAreTheDaysAndTheSessions() {
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let days = [
            TrackDay(date: when, car: "Miata"), TrackDay(date: when, car: "Elise"), TrackDay(date: when, car: " "),
        ]
        // "Miata" on two sessions and a day; "Elise" on a day with no session yet; no car is not a car.
        #expect(LogbookFilter.knownCars(in: entries, days: days) == ["Miata", "Elise", "GR86"])
        #expect(LogbookFilter.knownCars(in: [], days: []).isEmpty)
    }
}
