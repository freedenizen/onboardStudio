import Foundation

/// Compares the lap in progress with the best completed lap by distance travelled, which is
/// what a "delta" readout and a lap-vs-lap graph need.
public enum LapComparison {
    /// The first time in `start...end` at which the (non-decreasing) `distance` channel reaches
    /// `distance`, interpolated between samples. `nil` if it is never reached in the range.
    public static func time(
        atDistance distance: Double, in channel: Channel, between start: Double, and end: Double
    ) -> Double? {
        guard !channel.isEmpty, end > start else { return nil }
        let lower = channel.times.firstIndex(atOrAfter: start)
        let upper = min(channel.times.firstIndex(atOrAfter: end), channel.count - 1)
        guard lower <= upper else { return nil }
        let values = channel.values
        // Binary search on the monotonic slice.
        var low = lower
        var high = upper
        while low < high {
            let mid = (low + high) / 2
            if values[mid] < distance { low = mid + 1 } else { high = mid }
        }
        guard values[low] >= distance else { return nil }
        if low == lower || values[low] == distance { return channel.times[low] }
        let previous = low - 1
        let span = values[low] - values[previous]
        let fraction = span > 0 ? (distance - values[previous]) / span : 0
        return channel.times[previous] + (channel.times[low] - channel.times[previous]) * fraction
    }

    /// Distance travelled since `lap` started, at `time`.
    public static func distanceIntoLap(at time: Double, lap: Lap, distance: Channel) -> Double? {
        guard let now = distance.value(at: time), let start = distance.value(at: lap.start) else { return nil }
        return max(0, now - start)
    }

    /// Length of a completed lap in metres.
    public static func length(of lap: Lap, distance: Channel) -> Double? {
        guard let end = lap.end, let startValue = distance.value(at: lap.start), let endValue = distance.value(at: end)
        else { return nil }
        return max(0, endValue - startValue)
    }

    /// Which completed lap a delta is measured against.
    public enum Reference: Sendable, Equatable {
        /// The fastest lap completed before now.
        case best
        /// The lap completed just before the one in progress.
        case previous
    }

    /// The completed lap `reference` names at `time`, or `nil` when there is none yet.
    public static func referenceLap(at time: Double, session: TelemetrySession, reference: Reference) -> Lap? {
        let timing = LapTiming.resolve(at: time, laps: session.laps)
        switch reference {
        case .best:
            return timing.bestLapNumber.flatMap { number in session.laps.first { $0.number == number } }
        case .previous:
            guard let current = timing.currentLap else { return nil }
            return session.laps.last { $0.isComplete && ($0.end ?? .infinity) <= current.start }
        }
    }

    /// The moment in the reference lap when the car was as far into it as it is into the current
    /// lap now, with the current lap. `nil` without a distance channel, a current lap, a reference
    /// lap, or when the car is further into the lap than the reference lap went.
    struct Match {
        let current: Lap
        let reference: Lap
        let referenceTime: Double
    }

    static func matchingMoment(at time: Double, session: TelemetrySession, reference: Reference) -> Match? {
        guard let distance = session[.distance] else { return nil }
        let timing = LapTiming.resolve(at: time, laps: session.laps)
        guard let current = timing.currentLap,
            let lap = referenceLap(at: time, session: session, reference: reference), let end = lap.end,
            let into = distanceIntoLap(at: time, lap: current, distance: distance),
            let startDistance = distance.value(at: lap.start),
            let then = Self.time(atDistance: startDistance + into, in: distance, between: lap.start, and: end)
        else { return nil }
        return Match(current: current, reference: lap, referenceTime: then)
    }

    /// Seconds the lap in progress is behind (positive) or ahead of (negative) the reference lap at
    /// the same distance into the lap. `nil` when there is no such lap, no distance channel, or
    /// the car is further into the lap than the reference lap went.
    public static func delta(at time: Double, session: TelemetrySession, reference: Reference) -> Double? {
        guard let match = matchingMoment(at: time, session: session, reference: reference) else { return nil }
        return (time - match.current.start) - (match.referenceTime - match.reference.start)
    }

    /// `delta(at:session:reference: .best)`.
    public static func deltaToBest(at time: Double, session: TelemetrySession) -> Double? {
        delta(at: time, session: session, reference: .best)
    }
}

extension TimeParsing {
    /// `m:ss.f…` with `decimals` fractional digits (hours are prefixed when non-zero).
    public static func lapTimeString(_ seconds: Double, decimals: Int) -> String {
        let places = max(0, min(3, decimals))
        let total = max(0, seconds)
        let hours = Int(total / 3600)
        let minutes = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = total.truncatingRemainder(dividingBy: 60)
        let secondsWidth = places == 0 ? 2 : 3 + places
        let secondsText = String(format: "%0\(secondsWidth).\(places)f", secs)
        if hours > 0 {
            return "\(hours):" + String(format: "%02d", minutes) + ":" + secondsText
        }
        return "\(minutes):" + secondsText
    }

    /// `+1.23` / `−0.45` style delta with `decimals` fractional digits.
    public static func deltaString(_ seconds: Double, decimals: Int) -> String {
        let places = max(0, min(3, decimals))
        let magnitude = String(format: "%.\(places)f", abs(seconds))
        let rounded = Double(magnitude) ?? 0
        if rounded == 0 { return String(format: "%.\(places)f", 0.0) }
        return (seconds < 0 ? "−" : "+") + magnitude
    }
}

extension LapComparison {
    /// Speed now minus the best completed lap's speed at the same distance into the lap (m/s;
    /// positive = faster than the best lap here). `nil` under the same conditions as `deltaToBest`.
    public static func speedDeltaToBest(at time: Double, session: TelemetrySession) -> Double? {
        speedDelta(at: time, session: session, reference: .best)
    }

    /// Speed now minus the reference lap's speed at the same distance into the lap (m/s).
    public static func speedDelta(at time: Double, session: TelemetrySession, reference: Reference) -> Double? {
        guard let speed = session[.speed], let match = matchingMoment(at: time, session: session, reference: reference),
            let now = speed.value(at: time), let then = speed.value(at: match.referenceTime)
        else { return nil }
        return now - then
    }
}
