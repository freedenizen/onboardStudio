import Foundation

/// What the Logbook window shows of the logbook (#347): one scope from its sidebar — everything,
/// a circuit, a car or a year — narrowed by a search, so the choosing is testable without a view.
public enum LogbookScope: Hashable, Sendable {
    case all
    /// `id` is the entry's `circuitID` when it has one, else its track name; empty for the
    /// sessions that name no circuit (#455), which the sidebar gathers as "No circuit".
    case circuit(id: String, title: String)
    case car(String)
    case year(Int)
    /// One track day (#392); `title` is the day's label, "23 Aug 2026 · Sonoma".
    case day(id: UUID, title: String)

    /// What the sidebar calls the sessions that name no circuit (#455).
    public static let noCircuit = "No circuit"

    public var title: String {
        switch self {
        case .all: "All Sessions"
        case .circuit(let id, let title): id.isEmpty ? Self.noCircuit : title
        case .day(_, let title): title
        case .car(let car): car.isEmpty ? "No car" : car
        case .year(let year): String(year)
        }
    }
}

public enum LogbookFilter {
    public struct Group: Hashable, Sendable {
        public var scope: LogbookScope
        public var count: Int
    }

    /// The key a circuit is grouped under: the catalogue id, else the track name the file or its
    /// day gave it. Empty when the session names no circuit (#455). The key used to fall back to
    /// the file's name, so every file from an unrecognised place became a circuit of its own in
    /// the sidebar — `track`, `activity`, `generic` — and two files that happened to be named
    /// alike were taken for two visits to one place.
    public static func circuitKey(of entry: LogbookEntry) -> String {
        if let id = entry.circuitID { return id }
        let name = entry.trackName?.trimmingCharacters(in: .whitespaces) ?? ""
        return name
    }

    /// The sidebar's circuits, most sessions first, then by name; the sessions that name no
    /// circuit last, as one entry, the way the cars list ends with "No car".
    public static func circuits(in entries: [LogbookEntry]) -> [Group] {
        var counts: [String: (title: String, count: Int)] = [:]
        for entry in entries {
            let key = circuitKey(of: entry)
            counts[key, default: (key.isEmpty ? LogbookScope.noCircuit : entry.title, 0)].count += 1
        }
        return
            counts.map { Group(scope: .circuit(id: $0.key, title: $0.value.title), count: $0.value.count) }
            .sorted { lhs, rhs in
                if case .circuit(let id, _) = lhs.scope, id.isEmpty { return false }
                if case .circuit(let id, _) = rhs.scope, id.isEmpty { return true }
                return (lhs.count, rhs.scope.title) > (rhs.count, lhs.scope.title)
            }
    }

    /// The circuit names typed into the logbook, on its days and its sessions, most used first
    /// (#455): what a day's Circuit field offers beside the catalogue, so a circuit the catalogue
    /// does not know is spelt the same way on its second visit.
    public static func typedCircuits(in entries: [LogbookEntry], days: [TrackDay]) -> [String] {
        var counts: [String: Int] = [:]
        let names = entries.filter { $0.circuitID == nil }.map(\.trackName) + days.map(\.trackName)
        for name in names.compactMap({ $0?.trimmingCharacters(in: .whitespaces) }) where !name.isEmpty {
            counts[name, default: 0] += 1
        }
        return counts.sorted { lhs, rhs in
            lhs.value != rhs.value
                ? lhs.value > rhs.value : lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
        .map(\.key)
    }

    /// The sidebar's cars, most sessions first; the sessions with no car last, if any.
    public static func cars(in entries: [LogbookEntry]) -> [Group] {
        var counts: [String: Int] = [:]
        for entry in entries { counts[entry.car.trimmingCharacters(in: .whitespaces), default: 0] += 1 }
        return
            counts.map { Group(scope: .car($0.key), count: $0.value) }
            .sorted { lhs, rhs in
                if case .car(let a) = lhs.scope, a.isEmpty { return false }
                if case .car(let b) = rhs.scope, b.isEmpty { return true }
                return (lhs.count, rhs.scope.title) > (rhs.count, lhs.scope.title)
            }
    }

    /// The cars the logbook names, on its days and on its sessions, most used first (#453): what
    /// a Car field offers. One list for the sheet that begins a day and the field that corrects a
    /// session — the sheet used to prefill the last day's car and offer the sessions' beside it,
    /// and the two could disagree.
    public static func knownCars(in entries: [LogbookEntry], days: [TrackDay]) -> [String] {
        var counts: [String: Int] = [:]
        for name in entries.map(\.car) + days.map(\.car) {
            let car = name.trimmingCharacters(in: .whitespaces)
            if !car.isEmpty { counts[car, default: 0] += 1 }
        }
        return counts.sorted { lhs, rhs in
            lhs.value != rhs.value
                ? lhs.value > rhs.value : lhs.key.localizedStandardCompare(rhs.key) == .orderedAscending
        }
        .map(\.key)
    }

    /// The sidebar's years, newest first; undated sessions are not a year.
    public static func years(in entries: [LogbookEntry]) -> [Group] {
        var counts: [Int: Int] = [:]
        for entry in entries { if let year = entry.year { counts[year, default: 0] += 1 } }
        return counts.map { Group(scope: .year($0.key), count: $0.value) }.sorted { lhs, rhs in
            guard case .year(let a) = lhs.scope, case .year(let b) = rhs.scope else { return false }
            return a > b
        }
    }

    /// The sidebar's days, newest first, each with how many sessions it holds — a day with none
    /// is listed too, since a day is begun before its files exist.
    public static func days(in entries: [LogbookEntry], days: [TrackDay]) -> [Group] {
        var counts: [UUID: Int] = [:]
        for entry in entries { if let id = entry.trackDayID { counts[id, default: 0] += 1 } }
        return
            days
            .sorted { ($0.date, $0.added) > ($1.date, $1.added) }
            .map { Group(scope: .day(id: $0.id, title: $0.label), count: counts[$0.id] ?? 0) }
    }

    public static func matches(_ entry: LogbookEntry, scope: LogbookScope) -> Bool {
        switch scope {
        case .all: true
        case .day(let id, _): entry.trackDayID == id
        case .circuit(let id, _): circuitKey(of: entry) == id
        case .car(let car): entry.car.trimmingCharacters(in: .whitespaces) == car
        case .year(let year): entry.year == year
        }
    }

    /// Case-insensitive, any word: the circuit, the car, the driver, the notes, the tags, the file.
    public static func matches(_ entry: LogbookEntry, search: String) -> Bool {
        let words = search.split(separator: " ").map { $0.lowercased() }
        guard !words.isEmpty else { return true }
        let fields = [
            entry.title, entry.car, entry.driver, entry.notes, entry.tags.joined(separator: " "),
            URL(fileURLWithPath: entry.file.path).lastPathComponent, entry.trackName ?? "",
        ]
        let haystack = fields.joined(separator: " ").lowercased()
        return words.allSatisfy { haystack.contains($0) }
    }

    public static func apply(_ entries: [LogbookEntry], scope: LogbookScope, search: String) -> [LogbookEntry] {
        entries.filter { matches($0, scope: scope) && matches($0, search: search) }
    }
}
