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
    ///
    /// Traffic marks (#571) are read corner by corner: a corner a mark covers is left out of that
    /// lap's readings and the lap's other corners still count. A marked lap is judged flying by
    /// its time with the marked stretches driven at the best lap's pace, so a lap spent behind a
    /// slower car is not thrown away whole, and its lap time is left out of the lap-time spread.
    public static func measure(
        in session: TelemetrySession, corners: [Corner], options: CoachingOptions = CoachingOptions()
    ) -> ConsistencyStats? {
        let complete = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.duration != nil }
        guard let best = complete.min(by: { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }),
            let bestTime = best.duration
        else { return nil }
        let limit = bestTime * (1 + options.flyingLapTolerance)
        let bestProfile =
            session.traffic.isEmpty ? nil : LapProfile(lap: best, in: session, stepMeters: options.stepMeters)
        var laps: [FlyingLap] = []
        for lap in complete {
            guard let duration = lap.duration else { continue }
            if session.isClearOfTraffic(lap) {
                if duration <= limit { laps.append(FlyingLap(lap: lap, profile: nil, clear: true)) }
                continue
            }
            guard let profile = LapProfile(lap: lap, in: session, stepMeters: options.stepMeters),
                let bestProfile,
                duration - trafficCost(of: profile, against: bestProfile, in: session.traffic) <= limit
            else { continue }
            laps.append(FlyingLap(lap: lap, profile: profile, clear: false))
        }
        guard laps.count >= 3 else { return nil }
        var readings: [Int: [CornerMetrics]] = [:]
        for entry in laps {
            guard let profile = entry.profile ?? LapProfile(lap: entry.lap, in: session, stepMeters: options.stepMeters)
            else { continue }
            for metrics in CornerMetrics.measure(corners: corners, of: profile, options: options.metrics) {
                if !entry.clear,
                    profile.traffic(
                        from: metrics.phaseStart, to: max(metrics.phaseStart, metrics.phaseEnd), in: session.traffic)
                        != nil
                {
                    continue
                }
                readings[metrics.index, default: []].append(metrics)
            }
        }
        let times = laps.filter(\.clear).compactMap(\.lap.duration)
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

    /// A lap read for consistency: the profile already made when its marks were weighed, and
    /// whether no mark touches it.
    struct FlyingLap {
        let lap: Lap
        let profile: LapProfile?
        let clear: Bool
    }

    /// Seconds `lap` spent in marked stretches beyond what `best` took over the same distances
    /// (scaled to its length): how much quicker the lap would have been driven at the best lap's
    /// pace there. Never negative.
    static func trafficCost(of lap: LapProfile, against best: LapProfile, in spans: [TrafficSpan]) -> Double {
        guard lap.count >= 2, lap.lengthMeters > 0 else { return 0 }
        let scale = best.lengthMeters / lap.lengthMeters
        var cost = 0.0
        for index in 0..<(lap.count - 1) {
            let middle = (lap.times[index] + lap.times[index + 1]) / 2
            guard spans.contains(where: { $0.start <= middle && middle <= $0.end }) else { continue }
            let own = lap.elapsed[index + 1] - lap.elapsed[index]
            let theirs =
                best.elapsed(atDistance: lap.distances[index + 1] * scale)
                - best.elapsed(atDistance: lap.distances[index] * scale)
            cost += own - theirs
        }
        return max(0, cost)
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
