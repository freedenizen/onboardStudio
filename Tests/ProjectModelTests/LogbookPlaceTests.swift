import Foundation
import Testing

@testable import ProjectModel

/// Where the Logbook window was, kept across launches (#701).
@Suite("The Logbook's place (#701)")
struct LogbookPlaceTests {
    func entry(_ name: String, circuit: String? = nil, car: String = "", year: Int = 2026, day: UUID? = nil)
        -> LogbookEntry
    {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 6, day: 1))
        var entry = LogbookEntry(
            file: .init(path: "/days/\(name).csv", contentHash: name, byteCount: 1, importerID: "x"),
            circuitID: circuit, trackName: nil, date: date, car: car, driver: "", notes: "", tags: [])
        entry.trackDayID = day
        return entry
    }

    @Test("Every choice of the sidebar comes back as it was kept")
    func roundTrip() throws {
        let id = UUID()
        let scopes: [LogbookScope] = [
            .all, .circuit(id: "test-circuit", title: "Test Circuit"), .circuit(id: "", title: ""), .car("GR86"),
            .car(""), .year(2026), .day(id: id, title: "1 Jun 2026 · Test Circuit"),
        ]
        for scope in scopes {
            let place = LogbookPlace(scope: scope, view: "trends", selection: [UUID(), UUID()])
            #expect(LogbookPlace(storageValue: place.storageValue) == place, "\(scope)")
        }
    }

    @Test("Nothing kept, or words this build cannot read, is no place")
    func unreadable() {
        #expect(LogbookPlace(storageValue: "") == nil)
        #expect(LogbookPlace(storageValue: "all") == nil)
        #expect(LogbookPlace(storageValue: #"{"scope":{"kind":"planet"},"view":"sessions","selection":[]}"#) == nil)
    }

    @Test("A day that is gone gives way to All Sessions; one renamed takes its new label")
    func days() {
        let day = TrackDay(date: Date(timeIntervalSince1970: 1_780_000_000), trackName: "Renamed Since")
        let session = entry("a", day: day.id)
        let kept = LogbookPlace(
            scope: .day(id: day.id, title: "An Old Label"), view: "sessions", selection: [session.id])

        let found = kept.resolved(in: [session], days: [day], cars: [])
        #expect(found.scope == .day(id: day.id, title: day.label))
        #expect(found.selection == [session.id] && found.view == "sessions")

        let gone = kept.resolved(in: [session], days: [], cars: [])
        #expect(gone.scope == .all)
        // The session is still in the logbook, and All Sessions shows it.
        #expect(gone.selection == [session.id])
    }

    @Test("A circuit or a year with no session left gives way to All Sessions")
    func circuitsAndYears() {
        let here = entry("a", circuit: "test-circuit")
        let circuit = LogbookPlace(
            scope: .circuit(id: "test-circuit", title: "Test Circuit"), view: "trends", selection: [])
        #expect(circuit.resolved(in: [here], days: [], cars: []) == circuit)
        #expect(circuit.resolved(in: [entry("b", circuit: "elsewhere")], days: [], cars: []).scope == .all)
        // The view is kept either way.
        #expect(circuit.resolved(in: [], days: [], cars: []).view == "trends")

        let year = LogbookPlace(scope: .year(2026), view: "season", selection: [])
        #expect(year.resolved(in: [here], days: [], cars: []) == year)
        #expect(year.resolved(in: [entry("c", year: 2024)], days: [], cars: []).scope == .all)
    }

    @Test("A car is kept while a session or the garage still has it")
    func cars() {
        let place = LogbookPlace(scope: .car("GR86"), view: "sessions", selection: [])
        #expect(place.resolved(in: [entry("a", car: "GR86")], days: [], cars: []) == place)
        #expect(place.resolved(in: [entry("a", car: "Miata")], days: [], cars: []).scope == .all)
        #expect(place.resolved(in: [], days: [], cars: [Car(name: "GR86")]) == place)
    }

    @Test("Only sessions that still exist, and that the sidebar's choice shows, stay selected")
    func selection() {
        let shown = entry("a", car: "GR86")
        let hidden = entry("b", car: "Miata")
        let removed = UUID()
        let place = LogbookPlace(scope: .car("GR86"), view: "analysis", selection: [shown.id, hidden.id, removed])
        #expect(place.resolved(in: [shown, hidden], days: [], cars: []).selection == [shown.id])
        let all = LogbookPlace(scope: .all, view: "sessions", selection: [shown.id, hidden.id, removed])
        #expect(all.resolved(in: [shown, hidden], days: [], cars: []).selection == [shown.id, hidden.id])
    }

    @Test("The window's first moment is the place nothing is restored over")
    func start() {
        #expect(LogbookPlace.start == LogbookPlace(scope: .all, view: "sessions", selection: []))
    }
}
