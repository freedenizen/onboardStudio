import Foundation
import TelemetryKit

/// Goals in words (#461), for the circuit's card, an import's report and the Season.
extension Goal {
    /// "1:40.00 lap", "laps within 0.80 s", "turn 4 in 6.20 s", "92 km/h at turn 4's apex".
    public func title(speed: SpeedDisplayUnit) -> String {
        switch target {
        case .lapTime(let seconds): "\(LogbookTrends.lapTime(seconds)) lap"
        case .consistency(let seconds): String(format: "flying laps within %.2f s", seconds)
        case .cornerTime(let label, let seconds): String(format: "turn %@ in %.2f s", label, seconds)
        case .cornerSpeed(let label, let value): "\(Self.speed(value, in: speed)) at turn \(label)'s apex"
        }
    }

    /// The target in its own unit: "1:40.00", "0.80 s", "92 km/h".
    public func measure(_ value: Double, speed: SpeedDisplayUnit) -> String {
        switch target {
        case .lapTime: LogbookTrends.lapTime(value)
        case .consistency, .cornerTime: String(format: "%.2f s", value)
        case .cornerSpeed: Self.speed(value, in: speed)
        }
    }

    /// A difference in the target's unit: "2.31 s", "4 km/h".
    public func amount(_ value: Double, speed: SpeedDisplayUnit) -> String {
        if case .cornerSpeed = target { return Self.speed(value, in: speed) }
        return String(format: "%.2f s", value)
    }

    /// "92 km/h".
    public static func speed(_ metersPerSecond: Double, in unit: SpeedDisplayUnit) -> String {
        let symbol = unit == .kph ? "km/h" : unit.rawValue
        return "\(Int((metersPerSecond * unit.factorFromMetersPerSecond).rounded())) \(symbol)"
    }
}

extension GoalProgress {
    /// "Reached on 12 Oct 2026", "Best 1:42.31 — 2.31 s to go", "Nothing measured yet".
    public func status(speed: SpeedDisplayUnit) -> String {
        if let reachedOn {
            return "Reached on \(reachedOn.formatted(date: .abbreviated, time: .omitted))"
        }
        guard let best, let remaining else { return "Nothing measured yet" }
        return "Best \(goal.measure(best, speed: speed)) — \(goal.amount(remaining, speed: speed)) to go"
    }
}

/// What an import did for the goals at its circuits (#461), for its report: one reached, or closer.
public struct GoalNews: Sendable, Equatable, Identifiable {
    public var id: UUID { goal.id }
    public let goal: Goal
    public let reached: Bool
    public let sentence: String

    /// The goals at the circuits of the sessions `added`, read before and after them.
    public static func make(
        goals: [Goal], added: Set<UUID>, in entries: [LogbookEntry], speed: SpeedDisplayUnit
    ) -> [GoalNews] {
        let new = entries.filter { added.contains($0.id) }
        let earlier = entries.filter { !added.contains($0.id) }
        let titles = Dictionary(
            LogbookFilter.circuits(in: entries).compactMap { group -> (String, String)? in
                guard case .circuit(let id, let title) = group.scope else { return nil }
                return (id, title)
            }, uniquingKeysWith: { first, _ in first })
        return goals.compactMap { goal in
            guard !goal.sessions(in: new).isEmpty else { return nil }
            let before = GoalProgress.make(goal, entries: earlier)
            let after = GoalProgress.make(goal, entries: entries)
            let place = titles[goal.circuitKey] ?? goal.circuitKey
            let title = goal.title(speed: speed)
            if !before.isReached, after.isReached {
                return GoalNews(goal: goal, reached: true, sentence: "Goal reached: \(title) at \(place).")
            }
            guard !after.isReached, let now = after.remaining else { return nil }
            guard let was = before.remaining else {
                return GoalNews(
                    goal: goal, reached: false,
                    sentence: "\(goal.amount(now, speed: speed)) to go to your \(title) at \(place).")
            }
            guard was - now > 0.005 else { return nil }
            return GoalNews(
                goal: goal, reached: false,
                sentence: "\(goal.amount(now, speed: speed)) to go to your \(title) at \(place), "
                    + "\(goal.amount(was - now, speed: speed)) closer than before.")
        }
    }
}
