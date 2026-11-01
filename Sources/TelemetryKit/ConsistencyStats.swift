import Foundation

/// How repeatable the driver was across a session, corner by corner.
///
/// Coaches look at this before they look at speed: a corner driven the same way every lap can
/// be worked on; one driven differently every lap wants the same brake point first.
public struct ConsistencyStats: Sendable, Equatable, Codable {
    public struct CornerSpread: Sendable, Equatable, Codable {
        public let index: Int
        /// Laps the corner was read on.
        public let lapCount: Int
        public let brakePointMean: Double?
        /// Sample standard deviation of the brake point, metres; `nil` with fewer than two.
        public let brakePointSpread: Double?
        public let minimumSpeedMean: Double
        public let minimumSpeedSpread: Double?
        public let timeInCornerSpread: Double?
        /// Brake point within the tolerance and minimum speed within its fraction, or unknowable.
        public let isConsistent: Bool
    }

    public let lapCount: Int
    public let lapTimeMean: Double
    public let lapTimeSpread: Double
    public let corners: [CornerSpread]

    public func spread(ofCorner index: Int) -> CornerSpread? { corners.first { $0.index == index } }

    /// Over the session's flying laps: complete laps (short ones excluded) within
    /// `options.flyingLapTolerance` of the best. `nil` with fewer than three, which is too few
    /// to call anything a pattern.
    public static func measure(
        in session: TelemetrySession, corners: [Corner], options: CoachingOptions = CoachingOptions()
    ) -> ConsistencyStats? {
        let complete = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.duration != nil }
        guard let best = complete.compactMap(\.duration).min() else { return nil }
        let laps = complete.filter { ($0.duration ?? .infinity) <= best * (1 + options.flyingLapTolerance) }
        guard laps.count >= 3 else { return nil }
        var readings: [Int: [CornerMetrics]] = [:]
        for lap in laps {
            guard let profile = LapProfile(lap: lap, in: session, stepMeters: options.stepMeters) else { continue }
            for metrics in CornerMetrics.measure(corners: corners, of: profile, options: options.metrics) {
                readings[metrics.index, default: []].append(metrics)
            }
        }
        let times = laps.compactMap(\.duration)
        let spreads = readings.keys.sorted().compactMap { index -> CornerSpread? in
            guard let metrics = readings[index], metrics.count >= 2 else { return nil }
            let brakes = metrics.compactMap(\.brakePointMeters)
            let minimums = metrics.map(\.minimumSpeed)
            let brakeSpread = brakes.count >= 2 ? deviation(brakes) : nil
            let minimumSpread = deviation(minimums)
            let minimumMean = mean(minimums)
            let consistent =
                (brakeSpread.map { $0 <= options.consistentBrakeSpreadMeters } ?? true)
                && (minimumMean > 0 ? minimumSpread / minimumMean <= options.consistentSpeedSpreadFraction : true)
            return CornerSpread(
                index: index, lapCount: metrics.count, brakePointMean: brakes.isEmpty ? nil : mean(brakes),
                brakePointSpread: brakeSpread, minimumSpeedMean: minimumMean, minimumSpeedSpread: minimumSpread,
                timeInCornerSpread: deviation(metrics.map(\.timeInCorner)), isConsistent: consistent)
        }
        return ConsistencyStats(
            lapCount: laps.count, lapTimeMean: mean(times), lapTimeSpread: deviation(times), corners: spreads)
    }

    static func mean(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation; 0 with fewer than two values.
    static func deviation(_ values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        let average = mean(values)
        let variance = values.reduce(0) { $0 + ($1 - average) * ($1 - average) } / Double(values.count - 1)
        return variance.squareRoot()
    }
}
