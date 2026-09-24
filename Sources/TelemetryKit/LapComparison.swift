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

    /// A place on a lap, found by how far into the lap it is.
    ///
    /// What a sector boundary and a corner apex both are: they are recorded as distances, and
    /// anything that draws them needs a position.
    public struct LapPoint: Sendable, Equatable {
        public let time: Double
        public let latitude: Double
        public let longitude: Double
        /// Direction of travel there, degrees (0 = north), measured across the sample either side
        /// so a single noisy GPS fix cannot swing it.
        public let headingDegrees: Double

        public init(time: Double, latitude: Double, longitude: Double, headingDegrees: Double) {
            self.time = time
            self.latitude = latitude
            self.longitude = longitude
            self.headingDegrees = headingDegrees
        }
    }

    /// Where the car was `metres` into `lap`. `nil` without position, without a distance channel,
    /// or when the lap never got that far.
    public static func point(atDistanceInto lap: Lap, metres: Double, session: TelemetrySession) -> LapPoint? {
        guard let distance = session[.distance], let latitude = session[.latitude], let longitude = session[.longitude],
            let end = lap.end, let startDistance = distance.value(at: lap.start),
            let at = time(atDistance: startDistance + metres, in: distance, between: lap.start, and: end),
            let lat = latitude.value(at: at), let lon = longitude.value(at: at)
        else { return nil }
        // A step either side, so the heading reflects the track rather than one jittery fix.
        let step = 5.0
        let before = time(atDistance: startDistance + max(0, metres - step), in: distance, between: lap.start, and: end)
        let after = time(atDistance: startDistance + metres + step, in: distance, between: lap.start, and: end)
        var heading = session[.heading]?.value(at: at) ?? 0
        if let from = before, let to = after, let lat1 = latitude.value(at: from), let lon1 = longitude.value(at: from),
            let lat2 = latitude.value(at: to), let lon2 = longitude.value(at: to)
        {
            heading = DerivedChannels.bearing(lat1: lat1, lon1: lon1, lat2: lat2, lon2: lon2)
        }
        return LapPoint(time: at, latitude: lat, longitude: lon, headingDegrees: heading)
    }

    /// Which completed lap a delta is measured against.
    public enum Reference: Sendable, Equatable {
        /// The fastest full lap of the whole session, known from the first lap on.
        case sessionBest
        /// The fastest lap completed before now (what a live lap timer shows).
        case best
        /// The lap completed just before the one in progress.
        case previous
    }

    /// The completed lap `reference` names at `time`, or `nil` when there is none yet.
    public static func referenceLap(at time: Double, session: TelemetrySession, reference: Reference) -> Lap? {
        let timing = LapTiming.resolve(at: time, laps: session.laps)
        switch reference {
        case .sessionBest:
            return LapDeltas.sessionBest(in: session)
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

    /// What the lap in progress will come to if the rest of it goes as the reference lap's did:
    /// the reference lap's time plus the delta now (#155). On the reference lap itself it reads that
    /// lap's time throughout, and as a lap finishes it arrives at the lap's own time. `nil` under
    /// the same conditions as `delta`.
    public static func projectedLapTime(at time: Double, session: TelemetrySession, reference: Reference) -> Double? {
        guard let match = matchingMoment(at: time, session: session, reference: reference),
            let referenceTime = match.reference.duration
        else { return nil }
        return referenceTime + (time - match.current.start) - (match.referenceTime - match.reference.start)
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
