import Foundation

/// Trends narrowed to the sessions driven one way (#559): on one tyre set, one setup, one surface
/// or in one weather. Every part optional; nothing chosen is every session.
public struct TrendsFilter: Hashable, Sendable {
    public var tyres: String?
    /// The setup sheet's name.
    public var setup: String?
    public var surface: SessionConditions.Track?
    public var weather: SessionConditions.Weather?

    public init(
        tyres: String? = nil, setup: String? = nil, surface: SessionConditions.Track? = nil,
        weather: SessionConditions.Weather? = nil
    ) {
        self.tyres = tyres
        self.setup = setup
        self.surface = surface
        self.weather = weather
    }

    public var isEmpty: Bool { tyres == nil && setup == nil && surface == nil && weather == nil }

    public func matches(_ entry: LogbookEntry) -> Bool {
        let conditions = entry.conditions
        if let tyres, !Garage.same(conditions.tyres, tyres) { return false }
        if let setup, !Garage.same(conditions.sheet.name, setup) { return false }
        if let surface, conditions.track != surface { return false }
        if let weather, conditions.weather != weather { return false }
        return true
    }

    /// What each of Trends' pop-ups offers: the values the sessions noted, in the order they were
    /// first driven. A pop-up with fewer than two has nothing to narrow.
    public struct Choices: Hashable, Sendable {
        public var tyres: [String] = []
        public var setups: [String] = []
        public var surfaces: [SessionConditions.Track] = []
        public var weathers: [SessionConditions.Weather] = []
    }

    public static func choices(in entries: [LogbookEntry]) -> Choices {
        let ordered = entries.sorted { $0.when < $1.when }
        func distinct(_ values: [String]) -> [String] {
            values.reduce(into: [String]()) { kept, value in
                let trimmed = value.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, !kept.contains(where: { Garage.same($0, trimmed) }) { kept.append(trimmed) }
            }
        }
        func distinct<Value: Equatable>(_ values: [Value?]) -> [Value] {
            values.compactMap { $0 }.reduce(into: [Value]()) { kept, value in
                if !kept.contains(value) { kept.append(value) }
            }
        }
        return Choices(
            tyres: distinct(ordered.map(\.conditions.tyres)), setups: distinct(ordered.map(\.conditions.sheet.name)),
            surfaces: distinct(ordered.map(\.conditions.track)), weathers: distinct(ordered.map(\.conditions.weather)))
    }
}

extension LogbookTrends {
    /// The sessions at `circuitKey` (in `car`, when given), as `points` reads them.
    public static func entries(_ entries: [LogbookEntry], at circuitKey: String, car: String? = nil) -> [LogbookEntry] {
        guard !circuitKey.isEmpty else { return [] }
        return entries.filter { entry in
            LogbookFilter.circuitKey(of: entry) == circuitKey
                && (car.map { $0.isEmpty || entry.car.caseInsensitiveCompare($0) == .orderedSame } ?? true)
        }
    }
}
