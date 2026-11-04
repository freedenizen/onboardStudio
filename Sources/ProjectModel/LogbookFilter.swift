import Foundation

/// What the Logbook window shows of the logbook (#347): one scope from its sidebar — everything,
/// a circuit, a car or a year — narrowed by a search, so the choosing is testable without a view.
public enum LogbookScope: Hashable, Sendable {
    case all
    /// `id` is the entry's `circuitID` when it has one, else its track name, else nothing.
    case circuit(id: String, title: String)
    case car(String)
    case year(Int)
    /// One track day (#392); `title` is the day's label, "23 Aug 2026 · Sonoma".
    case day(id: UUID, title: String)

    public var title: String {
        switch self {
        case .all: "All Sessions"
        case .circuit(_, let title): title
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

    /// The key a circuit is grouped under: the catalogue id, else the track name, else the file.
    public static func circuitKey(of entry: LogbookEntry) -> String { entry.circuitID ?? entry.title }

    /// The sidebar's circuits, most sessions first, then by name.
    public static func circuits(in entries: [LogbookEntry]) -> [Group] {
        var counts: [String: (title: String, count: Int)] = [:]
        for entry in entries {
            let key = circuitKey(of: entry)
            counts[key, default: (entry.title, 0)].count += 1
        }
        return
            counts.map { Group(scope: .circuit(id: $0.key, title: $0.value.title), count: $0.value.count) }
            .sorted { ($0.count, $1.scope.title) > ($1.count, $0.scope.title) }
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
