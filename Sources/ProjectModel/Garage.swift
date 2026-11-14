import Foundation

/// The garage shown (#490) and filled (#489): what the logbook holds of a car, the days an
/// import left with none, and the corrections a car's name needs — a rename that reaches every
/// day and session, two spellings made one car, a name nothing uses any more taken out.
///
/// A car is named on days and sessions by its name; the garage (`garage.json`) holds one `Car`
/// per name, compared without regard to case, with the owner's notes.
public enum Garage {
    /// What the logbook holds of one car, for the header above its sessions.
    public struct Summary: Sendable, Equatable {
        public let sessions: Int
        /// The days its sessions are on, and the days that name it with none of them yet.
        public let days: Int
        public let circuits: Int
        public let first: Date?
        public let last: Date?

        /// No day or session names it: it can be taken out of the garage.
        public var isUnused: Bool { sessions == 0 && days == 0 }
    }

    /// Two names of one car: the same letters, whatever their case or the spaces around them.
    public static func same(_ lhs: String, _ rhs: String) -> Bool {
        lhs.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(rhs.trimmingCharacters(in: .whitespaces))
            == .orderedSame
    }

    /// The sessions and days named `car` exactly, as the sidebar's row for it lists them.
    public static func summary(of car: String, entries: [LogbookEntry], days: [TrackDay]) -> Summary {
        let name = car.trimmingCharacters(in: .whitespaces)
        let sessions = entries.filter { $0.car.trimmingCharacters(in: .whitespaces) == name }
        let named = days.filter { $0.car.trimmingCharacters(in: .whitespaces) == name }
        let dayIDs = Set(sessions.compactMap(\.trackDayID)).union(named.map(\.id))
        let circuits = Set(sessions.map(LogbookFilter.venueKey(of:)) + named.map(\.circuitKey)).subtracting([""])
        let dates = sessions.compactMap(\.date) + named.map(\.date)
        return Summary(
            sessions: sessions.count, days: dayIDs.count, circuits: circuits.count, first: dates.min(),
            last: dates.max())
    }

    /// The garage's car for `name`, if it has one.
    public static func car(named name: String, in cars: [Car]) -> Car? { cars.first { same($0.name, name) } }

    /// The days that sessions `added` went onto with no car (#489), oldest first: a first import
    /// has no earlier session at the circuit to take one from, so all of them, until the report
    /// asks. A day that names a car, or whose new sessions all have one, is not among them.
    public static func daysWithoutCar(added: Set<UUID>, entries: [LogbookEntry], days: [TrackDay]) -> [TrackDay] {
        let ids = Set(
            entries.filter { added.contains($0.id) && $0.car.trimmingCharacters(in: .whitespaces).isEmpty }
                .compactMap(\.trackDayID))
        return days.filter { ids.contains($0.id) && $0.car.trimmingCharacters(in: .whitespaces).isEmpty }
            .sorted { ($0.date, $0.added) < ($1.date, $1.added) }
    }
}

extension Logbook {
    /// A car named for the first time joins the garage, wherever it was typed.
    public func addToGarage(_ car: String) throws {
        let name = car.trimmingCharacters(in: .whitespaces)
        let cars = cars()
        guard !name.isEmpty, Garage.car(named: name, in: cars) == nil else { return }
        try saveCars(cars + [Car(name: name)])
    }

    /// Names the car of each of these days (#489), and of their sessions that had the day's —
    /// none, for the days an import left without one.
    public func setCar(_ car: String, onDays ids: [UUID]) throws {
        let name = car.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        for id in ids {
            guard var day = day(id: id) else { continue }
            day.car = name
            try updateDay(day)
        }
        try addToGarage(name)
    }

    /// Renames the car on every day and session that names it, and in the garage (#490): how a
    /// typo is put right once rather than day by day. A name another car already has makes the two
    /// one car, under that car's spelling, its notes followed by the renamed car's. Returns the
    /// name the car has now.
    @discardableResult
    public func renameCar(_ old: String, to new: String) throws -> String {
        let from = old.trimmingCharacters(in: .whitespaces)
        var to = new.trimmingCharacters(in: .whitespaces)
        guard !from.isEmpty, !to.isEmpty, from != to else { return from }
        let entries = entries()
        let days = days()
        var cars = cars()
        // Into another car: its spelling, as the logbook already writes it, is kept.
        if !Garage.same(from, to) {
            let names = entries.map(\.car) + days.map(\.car) + cars.map(\.name)
            to = names.map { $0.trimmingCharacters(in: .whitespaces) }.first { Garage.same($0, to) } ?? to
        }
        for var entry in entries where entry.car.trimmingCharacters(in: .whitespaces) == from {
            entry.car = to
            try save(entry)
        }
        for var day in days where day.car.trimmingCharacters(in: .whitespaces) == from {
            day.car = to
            try saveDay(day)
        }
        let source = cars.firstIndex { Garage.same($0.name, from) }
        let target = Garage.same(from, to) ? nil : cars.firstIndex { Garage.same($0.name, to) }
        switch (source, target) {
        case (let source?, let target?):
            var notes = [cars[target].notes, cars[source].notes]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            if notes.count == 2, notes[0] == notes[1] { notes.removeLast() }
            cars[target].notes = notes.joined(separator: "\n\n")
            cars.remove(at: source)
        case (let source?, nil): cars[source].name = to
        case (nil, nil): cars.append(Car(name: to))
        case (nil, _?): break
        }
        try saveCars(cars)
        return to
    }

    /// Takes the car out of the garage, with its notes — only once no day or session names it in
    /// any spelling, so a car still driven is never lost. Returns whether it was taken out.
    @discardableResult
    public func removeCar(named name: String) throws -> Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty,
            !entries().contains(where: { Garage.same($0.car, name) }),
            !days().contains(where: { Garage.same($0.car, name) })
        else { return false }
        let cars = cars()
        let kept = cars.filter { !Garage.same($0.name, name) }
        guard kept.count < cars.count else { return false }
        try saveCars(kept)
        return true
    }

    /// Takes out of the garage the names that say nothing: no notes, and no day or session names
    /// them in any spelling — what a typo leaves once it is put right on the day or the session
    /// (#490), and what a Car field would otherwise go on offering. A car with notes stays, listed
    /// with no sessions, until it is removed. `entries` and `days` are the logbook's, when the
    /// caller has just read them. Returns whether any was taken out.
    @discardableResult
    public func tidyGarage(entries: [LogbookEntry]? = nil, days: [TrackDay]? = nil) throws -> Bool {
        let cars = cars()
        let names = (entries ?? self.entries()).map(\.car) + (days ?? self.days()).map(\.car)
        let kept = cars.filter { car in
            !car.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || names.contains { Garage.same($0, car.name) }
        }
        guard kept.count < cars.count else { return false }
        try saveCars(kept)
        return true
    }

    /// The owner's notes on the car (#490); a car named only on days and sessions joins the garage
    /// with them.
    public func saveNotes(_ notes: String, forCar name: String) throws {
        let car = name.trimmingCharacters(in: .whitespaces)
        guard !car.isEmpty else { return }
        let text = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var cars = cars()
        if let index = cars.firstIndex(where: { Garage.same($0.name, car) }) {
            guard cars[index].notes != text else { return }
            cars[index].notes = text
        } else {
            cars.append(Car(name: car, notes: text))
        }
        try saveCars(cars)
    }
}
