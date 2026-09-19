import Foundation

/// Position-based deltas against the session's best lap, as channels any display object can use.
///
/// Every lap is aligned with the best lap by distance travelled since the lap started, so the
/// comparison is "same spot on the track":
/// - `lapDelta` (s): positive = behind the best lap here, negative = ahead.
/// - `speedDelta` (m/s): positive = faster than the best lap here.
///
/// The best lap is the quickest *full* lap of the whole session, so the first lap already has a
/// delta and the best lap itself reads zero. Out, in and otherwise partial laps get deltas too but
/// cannot be the reference: a lap must cover at least 90 % of the longest complete lap.
public enum LapDeltas {
    /// A complete lap shorter than this fraction of the longest complete lap is a partial lap.
    public static let fullLapFraction = 0.9

    /// Laps with complete-but-short laps marked incomplete, so a pit-lane fragment can never be the
    /// best lap anywhere (timers, counters, deltas). Without a distance channel laps are unchanged.
    public static func demotingShortLaps(_ laps: [Lap], distance: Channel?) -> [Lap] {
        guard let distance else { return laps }
        let lengths = laps.map { $0.isComplete ? LapComparison.length(of: $0, distance: distance) : nil }
        guard let longest = lengths.compactMap({ $0 }).max(), longest > 0 else { return laps }
        return zip(laps, lengths).map { lap, length in
            guard lap.isComplete, let length, length < longest * fullLapFraction else { return lap }
            return Lap(number: lap.number, start: lap.start, end: lap.end, isComplete: false)
        }
    }

    /// The quickest complete lap of the whole session (short laps excluded), if any.
    public static func sessionBest(in session: TelemetrySession) -> Lap? {
        demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.duration != nil }
            .min { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
    }

    /// `lapDelta` and, when the session has speed, `speedDelta`; empty without laps, a distance
    /// channel or a full lap to compare with.
    public static func channels(for session: TelemetrySession) -> [Channel] {
        guard let distance = session[.distance], let best = sessionBest(in: session),
            let profile = Profile(lap: best, distance: distance, speed: session[.speed])
        else { return [] }
        let sessionEnd = session.timeRange?.upperBound ?? distance.lastTime ?? 0
        var times: [Double] = []
        var timeDeltas: [Double] = []
        var speedDeltas: [Double] = []
        let speed = session[.speed]
        for lap in session.laps {
            let end = lap.end ?? sessionEnd
            guard end > lap.start, let startDistance = distance.value(at: lap.start) else { continue }
            var index = distance.times.firstIndex(atOrAfter: lap.start)
            while index < distance.count, distance.times[index] < end {
                let time = distance.times[index]
                let into = max(0, distance.values[index] - startDistance)
                times.append(time)
                timeDeltas.append((time - lap.start) - profile.elapsed(at: into))
                if let speed, let now = speed.value(at: time), let then = profile.speed(at: into) {
                    speedDeltas.append(now - then)
                } else {
                    speedDeltas.append(0)
                }
                index += 1
            }
        }
        guard !times.isEmpty else { return [] }
        var result = [
            Channel(role: .lapDelta, name: "Delta to best lap", unit: .seconds, times: times, values: timeDeltas)
        ]
        if speed != nil, profile.hasSpeed {
            result.append(
                Channel(
                    role: .speedDelta, name: "Speed vs best lap", unit: .metersPerSecond, times: times,
                    values: speedDeltas))
        }
        return result
    }

    /// The reference lap as functions of distance into the lap.
    struct Profile {
        private var distances: [Double] = []
        private var elapsed: [Double] = []
        private var speeds: [Double] = []
        let hasSpeed: Bool

        init?(lap: Lap, distance: Channel, speed: Channel?) {
            guard let end = lap.end, let startDistance = distance.value(at: lap.start),
                let endDistance = distance.value(at: end), endDistance > startDistance
            else { return nil }
            hasSpeed = speed != nil
            func append(_ time: Double, _ value: Double) {
                let into = value - startDistance
                // Strictly increasing distance keeps the interpolation well defined while stationary.
                if let last = distances.last, into <= last { return }
                distances.append(into)
                elapsed.append(time - lap.start)
                speeds.append(speed?.value(at: time) ?? 0)
            }
            append(lap.start, startDistance)
            var index = distance.times.firstIndex(atOrAfter: lap.start)
            while index < distance.count, distance.times[index] < end {
                append(distance.times[index], distance.values[index])
                index += 1
            }
            append(end, endDistance)
            guard distances.count >= 2 else { return nil }
        }

        /// Seconds the reference lap needed to get `distance` into the lap (clamped to the lap).
        func elapsed(at distance: Double) -> Double { interpolate(elapsed, at: distance) }

        /// The reference lap's speed `distance` into the lap.
        func speed(at distance: Double) -> Double? { hasSpeed ? interpolate(speeds, at: distance) : nil }

        private func interpolate(_ values: [Double], at distance: Double) -> Double {
            guard let first = distances.first, let last = distances.last else { return 0 }
            if distance <= first { return values[0] }
            if distance >= last { return values[values.count - 1] }
            var low = 0
            var high = distances.count - 1
            while high - low > 1 {
                let mid = (low + high) / 2
                if distances[mid] <= distance { low = mid } else { high = mid }
            }
            let span = distances[high] - distances[low]
            let fraction = span > 0 ? (distance - distances[low]) / span : 0
            return values[low] + (values[high] - values[low]) * fraction
        }
    }
}
