import Foundation

/// One edit of the logbook, as what it changed (#454): each session and day it touched, and the
/// garage, before and after. Edit ▸ Undo writes back the `before` of exactly these and nothing
/// else, so a session the Coaching window or an import wrote since is left as it is.
public struct LogbookChange: Sendable, Equatable {
    /// The logbook as read at one moment.
    public struct Snapshot: Sendable, Equatable {
        public var entries: [LogbookEntry]
        public var days: [TrackDay]
        public var cars: [Car]

        public init(entries: [LogbookEntry], days: [TrackDay], cars: [Car]) {
            self.entries = entries
            self.days = days
            self.cars = cars
        }
    }

    /// One thing before and after the edit; `nil` where it did not exist.
    public struct Pair<Value: Sendable & Equatable>: Sendable, Equatable {
        public var before: Value?
        public var after: Value?
    }

    public private(set) var entries: [UUID: Pair<LogbookEntry>] = [:]
    public private(set) var days: [UUID: Pair<TrackDay>] = [:]
    public private(set) var garage: Pair<[Car]>?

    /// What changed between two readings of the logbook.
    public init(from before: Snapshot, to after: Snapshot) {
        entries = Self.pairs(before.entries, after.entries)
        days = Self.pairs(before.days, after.days)
        if before.cars != after.cars { garage = Pair(before: before.cars, after: after.cars) }
    }

    private init(entries: [UUID: Pair<LogbookEntry>], days: [UUID: Pair<TrackDay>], garage: Pair<[Car]>?) {
        self.entries = entries
        self.days = days
        self.garage = garage
    }

    private static func pairs<T: Identifiable<UUID> & Sendable & Equatable>(_ before: [T], _ after: [T])
        -> [UUID: Pair<T>]
    {
        let old = Dictionary(before.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let new = Dictionary(after.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var pairs: [UUID: Pair<T>] = [:]
        for id in Set(old.keys).union(new.keys) where old[id] != new[id] {
            pairs[id] = Pair(before: old[id], after: new[id])
        }
        return pairs
    }

    public var isEmpty: Bool { entries.isEmpty && days.isEmpty && garage == nil }

    /// The edit taken back: what Undo writes, and then what Redo writes again.
    public var reversed: LogbookChange {
        LogbookChange(
            entries: entries.mapValues { Pair(before: $0.after, after: $0.before) },
            days: days.mapValues { Pair(before: $0.after, after: $0.before) },
            garage: garage.map { Pair(before: $0.after, after: $0.before) })
    }
}

extension Logbook {
    /// The logbook as it is on disk now.
    public func snapshot() -> LogbookChange.Snapshot {
        LogbookChange.Snapshot(entries: entries(), days: days(), cars: cars())
    }

    /// Writes the `after` side of the change: each session and day as it was then, with its own
    /// modification date, and taken out where it did not exist.
    public func apply(_ change: LogbookChange) throws {
        for (id, pair) in change.entries {
            if let entry = pair.after { try save(entry, keepingModified: true) } else { try remove(id: id) }
        }
        for (id, pair) in change.days {
            if let day = pair.after { try saveDay(day, keepingModified: true) } else { try removeDay(id: id) }
        }
        if let garage = change.garage { try saveCars(garage.after ?? []) }
    }
}

/// The names of the Logbook's edits in Edit ▸ Undo (#454), read from what an edit changed — the
/// fields of a session or a day are written whole, so the field is found by comparing them.
public enum LogbookEditName {
    public static func of(_ old: LogbookEntry, _ new: LogbookEntry) -> String {
        // A run's cones or its going off course (#552), the only change to its laps a driver makes.
        if old.laps.map(\.offCourse) != new.laps.map(\.offCourse) {
            let marked = zip(old.laps, new.laps).contains { !$0.offCourse && $1.offCourse }
            return marked ? "Mark Off Course" : "Mark Run Finished"
        }
        if old.laps.map(\.cones) != new.laps.map(\.cones) { return "Change Cones" }
        var changed: [String] = []
        if old.car != new.car { changed.append("Car") }
        if old.driver != new.driver { changed.append("Driver") }
        if old.notes != new.notes { changed.append("Notes") }
        if old.conditions != new.conditions { changed.append("Conditions") }
        if old.circuitID != new.circuitID || old.trackName != new.trackName { changed.append("Circuit") }
        if old.tags != new.tags { changed.append("Tags") }
        if old.trackDayID != new.trackDayID { changed.append("Track Day") }
        return changed.count == 1 ? "Change \(changed[0])" : "Change Session"
    }

    public static func of(_ old: TrackDay, _ new: TrackDay) -> String {
        if old.clips != new.clips, old.clips.count == new.clips.count { return "Assign Clip" }
        var changed: [String] = []
        if old.car != new.car { changed.append("Car") }
        if old.driver != new.driver { changed.append("Driver") }
        if old.notes != new.notes { changed.append("Notes") }
        if old.conditions != new.conditions { changed.append("Conditions") }
        if old.circuitKey != new.circuitKey { changed.append("Circuit") }
        if old.date != new.date { changed.append("Date") }
        if old.penaltyPerCone != new.penaltyPerCone { changed.append("Penalty per Cone") }
        return changed.count == 1 ? "Change \(changed[0])" : "Change Track Day"
    }

    /// "Remove Session", "Remove 3 Sessions".
    public static func removing(_ count: Int) -> String { count == 1 ? "Remove Session" : "Remove \(count) Sessions" }

    /// "Move Session", "Move 3 Sessions".
    public static func moving(_ count: Int) -> String { count == 1 ? "Move Session" : "Move \(count) Sessions" }
}
