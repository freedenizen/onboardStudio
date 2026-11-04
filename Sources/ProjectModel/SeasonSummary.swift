import Foundation
import TelemetryKit

/// A year of track days on one page (#355): how much was driven, where the bests fell, which
/// corner moved most, and what is still planned — everything the logbook already holds, composed.
public struct SeasonSummary: Sendable, Equatable {
    public struct CircuitBest: Sendable, Equatable, Identifiable {
        public var id: String { circuitKey }
        public var circuitKey: String
        public var title: String
        public var best: Double
        public var date: Date?
        public var car: String
        public var visits: Int
        /// Whether that best was a new personal best when it was set.
        public var isNewPersonalBest: Bool
    }

    public struct CornerMovement: Sendable, Equatable {
        public var circuitTitle: String
        public var label: String
        /// Seconds, negative = quicker through the corner than the visit before.
        public var change: Double
    }

    public struct OpenPlan: Sendable, Equatable, Identifiable {
        public var id: String { circuitTitle }
        public var circuitTitle: String
        public var experiments: [String]
    }

    public var year: Int
    public var car: String?
    public var trackDays: Int
    public var sessions: Int
    public var laps: Int
    /// Metres, over the sessions whose file recorded a distance; `nil` when none did.
    public var distanceMeters: Double?
    public var personalBestsSet: Int
    public var circuitBests: [CircuitBest]
    public var mostImproved: CornerMovement?
    public var mostCostly: CornerMovement?
    public var openPlans: [OpenPlan]

    /// The years the logbook has sessions in — by the day driven, or entered — newest first.
    public static func years(in entries: [LogbookEntry]) -> [Int] {
        Array(Set(entries.map { Self.year(of: $0) })).sorted(by: >)
    }

    public static func year(of entry: LogbookEntry) -> Int {
        Calendar(identifier: .gregorian).component(.year, from: entry.date ?? entry.added)
    }

    /// The season `year` (in `car`, when given), with the circuits' open plans from `plans`.
    public static func make(
        entries all: [LogbookEntry], year: Int, car: String? = nil, plans: [TrackDefinition] = []
    ) -> SeasonSummary {
        let calendar = Calendar(identifier: .gregorian)
        let entries = all.filter { entry in
            Self.year(of: entry) == year
                && (car.map { $0.isEmpty || entry.car.caseInsensitiveCompare($0) == .orderedSame } ?? true)
        }
        let days = Set(entries.map { calendar.startOfDay(for: $0.date ?? $0.added) })
        let distances = entries.compactMap(\.distanceMeters)
        let setters = PersonalBests.entriesSettingBests(in: all)
        var bests: [CircuitBest] = []
        for group in LogbookFilter.circuits(in: entries) {
            guard case .circuit(let key, let title) = group.scope,
                let best = PersonalBests.best(in: entries, circuitKey: key, car: car)
            else { continue }
            bests.append(
                CircuitBest(
                    circuitKey: key, title: title, best: best.seconds, date: best.date, car: best.car,
                    visits: group.count, isNewPersonalBest: setters.contains(best.entryID)))
        }
        var movements: [CornerMovement] = []
        for best in bests {
            for trend in LogbookTrends.cornerTrends(for: entries, circuitKey: best.circuitKey, car: car) {
                if let change = trend.timeChange {
                    movements.append(CornerMovement(circuitTitle: best.title, label: trend.label, change: change))
                }
            }
        }
        let visited = Set(bests.map(\.circuitKey))
        let open = plans.compactMap { definition -> OpenPlan? in
            guard visited.contains(definition.id), let plan = definition.plan, !plan.experiments.isEmpty else {
                return nil
            }
            let experiments = plan.experiments.map { "\($0.title): \($0.text)" }
            return OpenPlan(circuitTitle: definition.name, experiments: experiments)
        }
        return SeasonSummary(
            year: year, car: car, trackDays: days.count, sessions: entries.count,
            laps: entries.reduce(0) { $0 + $1.completeLapCount },
            distanceMeters: distances.isEmpty ? nil : distances.reduce(0, +),
            personalBestsSet: entries.filter { setters.contains($0.id) }.count, circuitBests: bests,
            mostImproved: movements.filter { $0.change < -0.005 }.min { $0.change < $1.change },
            mostCostly: movements.filter { $0.change > 0.005 }.max { $0.change < $1.change }, openPlans: open)
    }

    /// The headline numbers as words, for the card and for VoiceOver.
    public var lines: [String] {
        var lines = [
            "\(trackDays) track day\(trackDays == 1 ? "" : "s"), \(sessions) session\(sessions == 1 ? "" : "s"), "
                + "\(laps) lap\(laps == 1 ? "" : "s")"
        ]
        if let distanceMeters { lines.append(String(format: "%.0f km driven", distanceMeters / 1000)) }
        lines.append("\(personalBestsSet) personal best\(personalBestsSet == 1 ? "" : "s") set")
        for best in circuitBests {
            lines.append(
                "\(best.title): \(TimeParsing.lapTimeString(best.best))\(best.car.isEmpty ? "" : " in the \(best.car)")"
                    + (best.isNewPersonalBest ? " ★" : ""))
        }
        if let mostImproved {
            lines.append(
                "Most improved: \(mostImproved.circuitTitle) turn \(mostImproved.label), "
                    + String(format: "%.2f s quicker", -mostImproved.change))
        }
        if let mostCostly {
            lines.append(
                "Most costly: \(mostCostly.circuitTitle) turn \(mostCostly.label), "
                    + String(format: "%.2f s slower", mostCostly.change))
        }
        return lines
    }

    public var title: String { car.flatMap { $0.isEmpty ? nil : "\(year) in the \($0)" } ?? "Season \(year)" }
}
