import Foundation

/// What to know before going back to a circuit (#460): the personal best there, the last visit,
/// and the corners where that visit lost the most against the best — what the circuit's card in
/// the Logbook shows above its sessions, and a new day there shows until its first session.
public struct CircuitBrief: Sendable, Equatable {
    /// The latest day at the circuit.
    public struct Visit: Sendable, Equatable {
        public let date: Date
        /// The quickest complete lap of the day; `nil` when none was complete.
        public let best: Double?
        public let sessions: Int
    }

    /// A corner the last visit was slower through than the personal best's session.
    public struct Corner: Sendable, Equatable, Identifiable {
        public var id: String { label }
        public let label: String
        /// Seconds slower through the corner than on the best lap.
        public let timeLost: Double
        /// Metres; positive: the last visit braked earlier (further from the apex) than the best.
        public let brakedEarlierBy: Double?
        /// m/s; positive: the last visit was slower at the apex than the best.
        public let slowerAtApexBy: Double?

        /// "Turn 4".
        public var title: String { "Turn \(label)" }
    }

    public let circuitKey: String
    public let personalBest: PersonalBest?
    /// Track days at the circuit.
    public let visits: Int
    public let lastVisit: Visit?
    /// The last visit's corners slower than the best lap's by more than `noticeable`, the most first.
    public let cornersToWorkOn: [Corner]

    /// A difference of less than this in a corner is not worth a line.
    public static let noticeable = 0.05
    /// What the card lists, as a plan has: an instructor's three.
    public static let cornerCount = 3

    public static func make(entries: [LogbookEntry], circuitKey: String, calendar: Calendar = .current)
        -> CircuitBrief
    {
        let here = entries.filter { !circuitKey.isEmpty && LogbookFilter.circuitKey(of: $0) == circuitKey }
        let byDay = Dictionary(grouping: here) { calendar.startOfDay(for: $0.date ?? $0.added) }
        let last = byDay.max { $0.key < $1.key }.map { day, sessions in
            Visit(date: day, best: sessions.compactMap(\.bestLap).min(), sessions: sessions.count)
        }
        var corners: [Corner] = []
        // The latest day's best session against the personal best's, when they are two sessions.
        if let comparison = LogbookTrends.cornerComparison(for: here, circuitKey: circuitKey, calendar: calendar),
            comparison.best != nil
        {
            let slower = comparison.trends.compactMap { trend -> Corner? in
                guard let lost = trend.timeToBest, lost > noticeable else { return nil }
                return Corner(
                    label: trend.label, timeLost: lost, brakedEarlierBy: trend.brakePointToBest,
                    slowerAtApexBy: trend.minimumSpeedToBest.map { -$0 })
            }
            corners = Array(slower.sorted { $0.timeLost > $1.timeLost }.prefix(cornerCount))
        }
        return CircuitBrief(
            circuitKey: circuitKey, personalBest: PersonalBests.best(in: entries, circuitKey: circuitKey),
            visits: byDay.count, lastVisit: last, cornersToWorkOn: corners)
    }

    /// Nothing to say: no session at the circuit.
    public var isEmpty: Bool { visits == 0 }

    /// The corners to work on as a plan's experiments, each in a few words from what differed: how a
    /// plan is begun from the card when no Coaching window wrote one.
    public func startingPlan(made: Date = Date()) -> NextSessionPlan {
        let experiments =
            cornersToWorkOn.isEmpty
            ? [PlannedExperiment(cornerLabel: "", text: "")]
            : cornersToWorkOn.map { PlannedExperiment(cornerLabel: $0.label, text: Self.suggestion(for: $0)) }
        return NextSessionPlan(experiments: experiments, made: made)
    }

    /// "Brake later, as on your best lap" or "Carry more speed to the apex", from the larger of the
    /// two differences; the time alone when neither was read.
    static func suggestion(for corner: Corner) -> String {
        let lost = String(format: "%.2f s", corner.timeLost)
        if let earlier = corner.brakedEarlierBy, earlier > 2 {
            return "Brake later — \(Int(earlier.rounded())) m earlier than on your best lap, \(lost) lost."
        }
        if let slower = corner.slowerAtApexBy, slower > 0.3 {
            return "Carry more speed to the apex — \(lost) lost against your best lap."
        }
        return "Find the \(lost) your best lap was quicker through here."
    }
}
