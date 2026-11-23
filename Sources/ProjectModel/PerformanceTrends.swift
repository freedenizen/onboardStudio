import Foundation
import TelemetryKit

/// Performance runs across sessions (#553, step 3): every measured session's best launch, quarter
/// mile and stop, and each car's personal bests. A straight line is the car's, not the venue's, so
/// these are read across the whole logbook, by car, never by circuit.
public enum PerformanceTrends {
    /// One measured session's bests, in the measures of the speed unit it was asked for.
    public struct Point: Identifiable, Hashable, Sendable {
        public var id: UUID { entryID }
        public var entryID: UUID
        public var date: Date
        /// The car as the session names it; empty when it names none.
        public var car: String
        /// Seconds for 0–60 mph, or 0–100 km/h.
        public var launch: Double?
        /// Seconds to the quarter mile, with the 1-ft rollout, and its trap speed in m/s.
        public var quarterMile: Double?
        public var trap: Double?
        /// Metres from 60 mph, or 100 km/h, to standing still.
        public var stop: Double?
    }

    /// A personal best: the number, the trap speed for a quarter mile, and the session that set it.
    public struct Record: Hashable, Sendable {
        public var value: Double
        public var trap: Double?
        public var entryID: UUID
        public var date: Date
    }

    /// A car's personal bests. `car` is empty for the sessions that name no car.
    public struct CarBests: Identifiable, Hashable, Sendable {
        public var id: String { PerformanceTrends.key(car) }
        public var car: String
        public var launch: Record?
        public var quarterMile: Record?
        public var stop: Record?
    }

    /// The sessions with any of the three measured, in `car` when given, oldest first — by the day
    /// they were driven, or the day they were entered when the file carried no date.
    public static func points(for entries: [LogbookEntry], car: String? = nil, metric: Bool) -> [Point] {
        let launch = PerformanceWording.launch(metric: metric)
        let braking = PerformanceWording.braking(metric: metric)
        return
            entries
            .filter { entry in car.map { Garage.same(entry.car, $0) } ?? true }
            .sorted { $0.when < $1.when }
            .compactMap { entry in
                guard let performance = entry.performance else { return nil }
                let quarter = performance.best(.quarterMile)
                let point = Point(
                    entryID: entry.id, date: entry.when, car: entry.car,
                    launch: performance.best(launch)?.seconds, quarterMile: quarter?.seconds, trap: quarter?.trap,
                    stop: performance.best(braking)?.stop.metres)
                return point.launch == nil && point.quarterMile == nil && point.stop == nil ? nil : point
            }
    }

    /// Each car's personal bests, cars in name order and the sessions naming none last. The first
    /// session to reach a best keeps it: a later one that only equals it does not take it.
    public static func bests(in points: [Point]) -> [CarBests] {
        var cars: [String: CarBests] = [:]
        for point in points {
            let key = key(point.car)
            var bests = cars[key] ?? CarBests(car: point.car)
            func record(_ value: Double?, trap: Double? = nil, beating current: Record?) -> Record? {
                guard let value, value < current?.value ?? .infinity else { return current }
                return Record(value: value, trap: trap, entryID: point.entryID, date: point.date)
            }
            bests.launch = record(point.launch, beating: bests.launch)
            bests.quarterMile = record(point.quarterMile, trap: point.trap, beating: bests.quarterMile)
            bests.stop = record(point.stop, beating: bests.stop)
            cars[key] = bests
        }
        return cars.values.sorted { lhs, rhs in
            lhs.car.isEmpty != rhs.car.isEmpty
                ? !lhs.car.isEmpty : lhs.car.localizedStandardCompare(rhs.car) == .orderedAscending
        }
    }

    /// One car however its name is cased or spaced, as `Garage.same` reads it.
    static func key(_ car: String) -> String { car.trimmingCharacters(in: .whitespaces).lowercased() }

    /// A sentence for VoiceOver and the line under the heading: where the launch went, car by car.
    public static func summary(of points: [Point], metric: Bool) -> String {
        let label = PerformanceWording.launch(metric: metric).label
        let lines = bests(in: points).compactMap { bests -> String? in
            let timed = points.filter { Garage.same($0.car, bests.car) }.compactMap(\.launch)
            guard let first = timed.first, let best = bests.launch?.value else { return nil }
            let car = bests.car.isEmpty ? "With no car named" : "In the \(bests.car)"
            guard timed.count > 1 else {
                return "\(car), one \(label) so far: \(PerformanceWording.seconds(best))."
            }
            let change = LogbookTrends.change(from: first, to: best)
            return "\(car), \(label) \(PerformanceWording.seconds(first)) in the first session, "
                + "best \(PerformanceWording.seconds(best)): \(change)."
        }
        return lines.isEmpty ? "No \(label) measured yet." : lines.joined(separator: " ")
    }
}
