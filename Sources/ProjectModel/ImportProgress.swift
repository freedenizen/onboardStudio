import Foundation

/// What an import says about the driver's progress (#459): for each circuit the new sessions were
/// driven at, the day's best lap against the visit before it — and where the logbook shows more:
/// that circuit's Trends, or the Season when Trends has nothing to draw yet or the import spans
/// several circuits.
public struct ImportProgress: Sendable, Equatable {
    /// A day at a circuit and its quickest complete lap.
    public struct Visit: Sendable, Equatable {
        public let date: Date
        public let best: Double
    }

    /// The latest of the new days at one circuit, and how it compares.
    public struct Circuit: Sendable, Equatable, Identifiable {
        public var id: String { key }
        /// `LogbookFilter.circuitKey`.
        public let key: String
        /// What the sidebar calls the circuit, so the scope Show Trends chooses is the sidebar's row.
        public let title: String
        /// The day the new sessions were driven, the latest of them at this circuit.
        public let day: Date
        /// The quickest complete lap of that day's sessions — the new ones and any already in the
        /// logbook for the day; `nil` when none has one.
        public let best: Double?
        /// How many sessions the logbook has at the circuit on that day.
        public let sessions: Int
        /// The latest earlier day at the circuit with a complete lap.
        public let previous: Visit?
        /// The logbook has no other day at the circuit.
        public let isFirstVisit: Bool
        /// The logbook has a later day at the circuit: an old day added after newer ones.
        public let hasLaterVisits: Bool
        /// `best` is quicker than every session at the circuit on other days.
        public let isPersonalBest: Bool
        /// Trends draws a chart: two sessions or more at the circuit with a complete lap.
        public let hasTrend: Bool
    }

    /// Where the logbook shows more.
    public enum Destination: Sendable, Equatable {
        case trends(circuit: String, title: String)
        case season
    }

    /// Newest day first.
    public let circuits: [Circuit]

    public init(circuits: [Circuit]) { self.circuits = circuits }

    /// Two lap times closer than this are the same lap time, as they are written: to the
    /// hundredth.
    static let sameLap = 0.005

    /// The progress of the sessions `added` among `entries`, the whole logbook after the import.
    /// Sessions that name no circuit are not visits to a place (#455) and say nothing here.
    public static func make(added: Set<UUID>, in entries: [LogbookEntry], calendar: Calendar = .current)
        -> ImportProgress
    {
        func day(_ entry: LogbookEntry) -> Date { calendar.startOfDay(for: entry.date ?? entry.added) }
        let new = entries.filter { added.contains($0.id) }
        let keys = Set(new.map(LogbookFilter.circuitKey(of:))).subtracting([""])
        let titles = Dictionary(
            LogbookFilter.circuits(in: entries).compactMap { group -> (String, String)? in
                guard case .circuit(let id, let title) = group.scope else { return nil }
                return (id, title)
            }, uniquingKeysWith: { first, _ in first })
        let circuits = keys.compactMap { key -> Circuit? in
            let here = entries.filter { LogbookFilter.circuitKey(of: $0) == key }
            guard let latest = new.filter({ LogbookFilter.circuitKey(of: $0) == key }).map(day).max() else {
                return nil
            }
            let today = here.filter { day($0) == latest }
            let others = here.filter { day($0) != latest }
            let best = today.compactMap(\.bestLap).min()
            let previous = Dictionary(grouping: others.filter { day($0) < latest && $0.bestLap != nil }, by: day)
                .max { $0.key < $1.key }
                .flatMap { date, sessions in sessions.compactMap(\.bestLap).min().map { Visit(date: date, best: $0) } }
            let otherBest = others.compactMap(\.bestLap).min()
            return Circuit(
                key: key, title: titles[key] ?? today.first?.title ?? key, day: latest, best: best,
                sessions: today.count, previous: previous, isFirstVisit: others.isEmpty,
                hasLaterVisits: others.contains { day($0) > latest },
                isPersonalBest: best.flatMap { best in otherBest.map { best < $0 - sameLap } } ?? false,
                hasTrend: here.filter { $0.bestLap != nil }.count >= 2)
        }
        return ImportProgress(circuits: circuits.sorted { ($0.day, $1.title) > ($1.day, $0.title) })
    }

    /// Show Trends for the one circuit when Trends has a chart of it; the Season for a first
    /// session somewhere, or for several circuits at once; nowhere when no new session names a
    /// circuit.
    public var destination: Destination? {
        guard let first = circuits.first else { return nil }
        if circuits.count == 1, first.hasTrend { return .trends(circuit: first.key, title: first.title) }
        return .season
    }
}

extension ImportProgress.Circuit {
    /// The circuit's line in the import's report.
    public var sentence: String {
        let lap = best.map(LogbookTrends.lapTime)
        if isFirstVisit {
            guard let lap else { return "First visit to \(title). Trends begins with your next day there." }
            if hasTrend { return "First visit to \(title): best lap \(lap) over \(sessions) sessions." }
            return "First visit to \(title): best lap \(lap). Trends begins with your next day there."
        }
        guard let previous else {
            guard let lap else { return "\(title): no complete lap to compare." }
            return "\(title): best lap \(lap). No earlier visit has a lap time to compare it with."
        }
        let visit =
            "\(hasLaterVisits ? "the visit before it" : "your last visit") (\(Self.date(previous.date, from: day)))"
        guard let lap, let best else { return "\(title): no complete lap this time to compare with \(visit)." }
        let gap = best - previous.best
        if abs(gap) < ImportProgress.sameLap { return "\(title): best lap \(lap), the same as \(visit)." }
        let change = "\(String(format: "%.2f", abs(gap))) s \(gap < 0 ? "quicker" : "slower")"
        return "\(title): best lap \(lap), \(change) than \(visit)\(isPersonalBest ? " — a personal best" : "")."
    }

    /// "12 Oct", with the year when it is not the year of `day`.
    static func date(_ date: Date, from day: Date) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: day)
        return sameYear
            ? date.formatted(.dateTime.day().month(.abbreviated))
            : date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
