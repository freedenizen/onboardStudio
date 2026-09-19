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

    /// Seconds the lap in progress is behind (positive) or ahead of (negative) the best completed
    /// lap at the same distance into the lap. `nil` when there is no best lap, no distance channel,
    /// or the car is further into the lap than the best lap went.
    public static func deltaToBest(at time: Double, session: TelemetrySession) -> Double? {
        guard let distance = session[.distance] else { return nil }
        let timing = LapTiming.resolve(at: time, laps: session.laps)
        guard let current = timing.currentLap, let bestNumber = timing.bestLapNumber,
            let best = session.laps.first(where: { $0.number == bestNumber }), let bestEnd = best.end,
            let into = distanceIntoLap(at: time, lap: current, distance: distance),
            let bestStartDistance = distance.value(at: best.start)
        else { return nil }
        guard
            let bestTime = Self.time(
                atDistance: bestStartDistance + into, in: distance, between: best.start, and: bestEnd)
        else { return nil }
        return (time - current.start) - (bestTime - best.start)
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
        guard let distance = session[.distance], let speed = session[.speed] else { return nil }
        let timing = LapTiming.resolve(at: time, laps: session.laps)
        guard let current = timing.currentLap, let bestNumber = timing.bestLapNumber,
            let best = session.laps.first(where: { $0.number == bestNumber }), let bestEnd = best.end,
            let into = distanceIntoLap(at: time, lap: current, distance: distance),
            let bestStartDistance = distance.value(at: best.start),
            let bestTime = Self.time(
                atDistance: bestStartDistance + into, in: distance, between: best.start, and: bestEnd),
            let now = speed.value(at: time), let then = speed.value(at: bestTime)
        else { return nil }
        return now - then
    }
}
