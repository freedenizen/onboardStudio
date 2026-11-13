import Foundation
import TelemetryKit

/// What a driver is aiming for at a circuit (#461): a lap time, how consistent a session's laps
/// are, or a corner — in any car or one, by a date or not. The logbook recorded what happened and
/// nothing of what the driver was after, so progress had nothing to be measured against.
public struct Goal: Identifiable, Hashable, Codable, Sendable {
    public enum Target: Hashable, Codable, Sendable {
        /// A best lap of at most this.
        case lapTime(seconds: Double)
        /// A session whose flying laps spread by at most this (`LogbookTrends.lapSpread`).
        case consistency(seconds: Double)
        /// Through the corner in at most this, on a session's best lap.
        case cornerTime(label: String, seconds: Double)
        /// At least this speed at the corner's apex, on a session's best lap.
        case cornerSpeed(label: String, metersPerSecond: Double)

        /// The value is better when lower: every target but the apex speed.
        public var lowerIsBetter: Bool {
            if case .cornerSpeed = self { return false }
            return true
        }

        public var value: Double {
            switch self {
            case .lapTime(let seconds), .consistency(let seconds), .cornerTime(_, let seconds): seconds
            case .cornerSpeed(_, let speed): speed
            }
        }

        public var cornerLabel: String? {
            switch self {
            case .cornerTime(let label, _), .cornerSpeed(let label, _): label
            case .lapTime, .consistency: nil
            }
        }
    }

    public var id: UUID
    /// `LogbookFilter.circuitKey`.
    public var circuitKey: String
    public var target: Target
    /// The car it is to be done in; empty: any.
    public var car: String
    /// The day to reach it by; `nil`: no date.
    public var by: Date?
    public var set: Date

    public init(
        id: UUID = UUID(), circuitKey: String, target: Target, car: String = "", by: Date? = nil, set: Date = Date()
    ) {
        self.id = id
        self.circuitKey = circuitKey
        self.target = target
        self.car = car
        self.by = by
        // Whole seconds: the file writes dates as ISO 8601, and a goal read back must still equal it.
        self.set = Date(timeIntervalSince1970: set.timeIntervalSince1970.rounded())
    }

    /// What the session measures for the goal; `nil` when it says nothing of it — no complete lap,
    /// fewer than three flying laps, the corner not read.
    public func value(of entry: LogbookEntry) -> Double? {
        switch target {
        case .lapTime: entry.bestLap
        case .consistency: LogbookTrends.lapSpread(of: entry)
        case .cornerTime(let label, _): entry.corners.first { $0.label == label }?.timeInCorner
        case .cornerSpeed(let label, _): entry.corners.first { $0.label == label }?.minimumSpeed
        }
    }

    /// The sessions it is measured on: at its circuit, in its car when it names one.
    public func sessions(in entries: [LogbookEntry]) -> [LogbookEntry] {
        entries.filter { entry in
            let driven = entry.car.trimmingCharacters(in: .whitespaces)
            return LogbookFilter.circuitKey(of: entry) == circuitKey
                && (car.isEmpty || driven.caseInsensitiveCompare(car) == .orderedSame)
        }
    }

    public func meets(_ value: Double) -> Bool {
        target.lowerIsBetter ? value <= target.value : value >= target.value
    }

    /// The better of two values, in the goal's direction.
    func better(_ lhs: Double, _ rhs: Double) -> Double {
        target.lowerIsBetter ? min(lhs, rhs) : max(lhs, rhs)
    }
}

/// How far a goal has come (#461), from the sessions it is measured on.
public struct GoalProgress: Sendable, Equatable, Identifiable {
    public var id: UUID { goal.id }
    public let goal: Goal
    /// The best any session has done, in the goal's measure.
    public let best: Double?
    /// The newest session's, when it measured anything.
    public let latest: Double?
    /// The day of the first session that met the target, and that session.
    public let reachedOn: Date?
    public let reachedBy: UUID?

    public var isReached: Bool { reachedOn != nil }

    /// What is still to find: seconds to take off, or speed to add; zero once reached.
    public var remaining: Double? {
        guard let best else { return nil }
        let gap = goal.target.lowerIsBetter ? best - goal.target.value : goal.target.value - best
        return max(gap, 0)
    }

    public static func make(_ goal: Goal, entries: [LogbookEntry]) -> GoalProgress {
        let measured = goal.sessions(in: entries).compactMap { entry in
            goal.value(of: entry).map { (entry: entry, value: $0) }
        }
        let best = measured.map(\.value).reduce(nil) { best, value in best.map { goal.better($0, value) } ?? value }
        let dated = measured.filter { $0.entry.date != nil }.sorted {
            ($0.entry.date ?? .distantPast) < ($1.entry.date ?? .distantPast)
        }
        let first = dated.first { goal.meets($0.value) }
        return GoalProgress(
            goal: goal, best: best, latest: dated.last?.value, reachedOn: first?.entry.date,
            reachedBy: first?.entry.id)
    }
}

// MARK: - Kept beside the garage

extension Logbook {
    public static let goalsFileName = "goals.json"

    public func goals() -> [Goal] {
        guard let data = try? Data(contentsOf: directory.appending(path: Self.goalsFileName)) else { return [] }
        return (try? Self.decoder.decode([Goal].self, from: data)) ?? []
    }

    public func saveGoals(_ goals: [Goal]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.encoder.encode(goals).write(to: directory.appending(path: Self.goalsFileName), options: .atomic)
    }
}
