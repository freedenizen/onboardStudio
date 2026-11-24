import Foundation
import TelemetryKit

/// Grip over visits (#558): each session's best lap read against the car's grip in that session's
/// conditions, oldest first, for the Trends chart beside consistency.
public enum GripTrends {
    public struct Point: Identifiable, Hashable, Sendable {
        public var id: UUID { entryID }
        public var entryID: UUID
        public var date: Date
        /// Share of the grip used braking and turning, 0–1.
        public var meanUsed: Double
        /// Share of the lap near the limit, 0–1.
        public var nearLimit: Double
        /// Corners where braking stopped before turning.
        public var gaps: Int
    }

    /// The sessions at `circuitKey` (in `car`, when given) whose grip was read, oldest first. Each
    /// car's grip is learned from `learningFrom` — every session, though Trends shows only those
    /// its filters leave (#559) — or from `entries` without it.
    public static func points(
        for entries: [LogbookEntry], circuitKey: String, car: String? = nil, cars: [Car] = [],
        learningFrom all: [LogbookEntry]? = nil, options: GripUse.Options = .init()
    ) -> [Point] {
        let learning = all ?? entries
        guard !circuitKey.isEmpty else { return [] }
        return entries.filter { entry in
            LogbookFilter.circuitKey(of: entry) == circuitKey
                && (car.map { $0.isEmpty || Garage.same(entry.car, $0) } ?? true)
        }
        .sorted { $0.when < $1.when }
        .compactMap { entry in
            let adjustment = Garage.car(named: entry.car, in: cars)?.gripAdjustment ?? 1
            guard let limit = CarGrip.limit(for: entry, among: learning, adjustment: adjustment),
                let use = entry.gripUse(against: limit)
            else { return nil }
            return Point(
                entryID: entry.id, date: entry.when, meanUsed: use.meanUsed,
                nearLimit: use.nearLimit,
                gaps: use.corners.filter { ($0.gap?.lowestUsed ?? 1) < options.gapBelow }.count)
        }
    }

    /// "Grip used went from 71% to 84% over 4 sessions; braking stopped before turning in 3 corners,
    /// then 1."; `nil` under two sessions.
    public static func summary(of points: [Point]) -> String? {
        guard let first = points.first, let last = points.last, points.count >= 2 else { return nil }
        let used =
            "Grip used went from \(GripWording.percent(first.meanUsed)) to \(GripWording.percent(last.meanUsed)) "
            + "over \(points.count) sessions"
        guard first.gaps != last.gaps else { return used + "." }
        let corners = first.gaps == 1 ? "1 corner" : "\(first.gaps) corners"
        return used + "; braking stopped before turning in \(corners), then \(last.gaps)."
    }
}
