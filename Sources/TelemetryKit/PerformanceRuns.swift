import Foundation

/// Standing starts and stops, as a GPS performance meter times them (#553): 0–60 mph and 0–100
/// km/h, 60 ft to the quarter mile with trap speeds, 60–0 mph and 100–0 km/h.
///
/// - **An attempt** begins where the car moves off from standing still and lasts until the driver
///   lifts — speed more than `liftDrop` below its highest so far — or the car stands still again.
///   A measure the attempt never reached is absent, so a launch abandoned at 40 mph still has its
///   0–30.
/// - **Speed times** run from the moment the car started moving: the crossing of `movingSpeed`,
///   taken back to zero speed along the acceleration there, so a 10 Hz log does not lose the
///   moment the car took to reach walking pace. They have no rollout, as magazines quote them.
/// - **Distance times** have a timeslip's **1-ft rollout**: the clock starts once the car has
///   rolled a foot, where a drag strip's beam would see it go, and the distance is measured from
///   there. That makes a quarter mile 0.2–0.3 s quicker than timed from the first movement.
/// - **Trap speed** is the mean over the last 66 ft before the mark, as a strip's trap measures it.
/// - **A stop** runs from the moment speed falls through the braking speed to standing still, with
///   no rise of more than `stopRise` on the way.
///
/// Every crossing — a speed reached, a distance covered — is interpolated between samples.
/// Nothing here decides which sessions are worth measuring: a circuit's pit exit is a standing
/// start too. The caller asks.
public enum PerformanceRuns {
    /// One standing start and what it reached.
    public struct Attempt: Sendable, Equatable {
        /// Session seconds: when the car started moving, and when the attempt ended.
        public let start: Double
        public let end: Double
        /// Seconds for each speed range the attempt covered.
        public var speedTimes: [SpeedRange: Double] = [:]
        /// Seconds to each mark, with the 1-ft rollout.
        public var distanceTimes: [DragDistance: Double] = [:]
        /// Mean speed (m/s) over the 66 ft before the eighth and the quarter.
        public var trapSpeeds: [DragDistance: Double] = [:]
        /// Rise over run across the attempt: 0.018 is 1.8 % uphill, −0.018 downhill. `nil` without
        /// an altitude channel.
        public var slope: Double?
        /// Samples a second of the speed channel over the attempt.
        public var sampleHertz: Double

        public init(start: Double, end: Double, sampleHertz: Double) {
            self.start = start
            self.end = end
            self.sampleHertz = sampleHertz
        }
    }

    /// One stop from a braking speed to standing still.
    public struct Stop: Sendable, Equatable {
        public let from: BrakingSpeed
        /// Session seconds: speed falling through `from`, and the car standing still.
        public let start: Double
        public let end: Double
        public let metres: Double
        public var slope: Double?
        public var seconds: Double { end - start }
    }

    public struct Result: Sendable, Equatable {
        public var attempts: [Attempt] = []
        public var stops: [Stop] = []
    }

    public struct Options: Sendable, Equatable {
        /// Faster than this the car is moving (m/s); slower, it stands still.
        public var movingSpeed = 0.5
        /// An attempt is over once speed falls this far below its highest so far (m/s).
        public var liftDrop = 3.0
        /// A stop is not one if speed rises this much on the way down (m/s).
        public var stopRise = 1.0
        /// A timeslip's rollout (m).
        public var rollout = 0.3048
        /// A strip's trap (m): the last 66 ft before the mark.
        public var trapLength = 66 * 0.3048
        /// Over this the slope is worth a note.
        public static let notableSlope = 0.01
        /// Under this many samples a second the times deserve a note.
        public static let notableRate = 10.0

        public init() {}
    }

    /// Every standing start and every stop in `session`; empty without a speed channel.
    public static func measure(in session: TelemetrySession, options: Options = Options()) -> Result {
        guard let speed = session[.speed], speed.count > 2 else { return Result() }
        let track = SpeedTrack(speed: speed)
        let ground = Ground(distance: session[.distance], altitude: session[.altitude], speed: speed)
        var result = Result()
        var index = 1
        while index < speed.count {
            guard speed.values[index - 1] < options.movingSpeed, speed.values[index] >= options.movingSpeed else {
                index += 1
                continue
            }
            let (attempt, next) = attempt(launchingAt: index, track: track, ground: ground, options: options)
            if let attempt { result.attempts.append(attempt) }
            index = max(next, index + 1)
        }
        for braking in BrakingSpeed.allCases {
            result.stops += stops(from: braking, track: track, ground: ground, options: options)
        }
        result.stops.sort { $0.start < $1.start }
        return result
    }

    // MARK: - Launches

    static func attempt(
        launchingAt index: Int, track: SpeedTrack, ground: Ground, options: Options
    ) -> (Attempt?, Int) {
        let values = track.values
        // Time zero: the crossing of the moving speed, taken back to zero along the acceleration.
        let crossing = track.crossing(upward: options.movingSpeed, between: index - 1, and: index)
        let accel = track.slope(between: index - 1, and: index)
        let start = accel > 0 ? crossing - options.movingSpeed / accel : crossing
        // Until the driver lifts or the car stands still.
        var top = values[index]
        var last = index
        while last + 1 < values.count {
            let next = values[last + 1]
            if next < options.movingSpeed || next < top - options.liftDrop { break }
            top = max(top, next)
            last += 1
        }
        let end = track.times[last]
        let hertz = Double(last - index + 1) / max(end - track.times[index - 1], 1e-9)
        var attempt = Attempt(start: start, end: end, sampleHertz: hertz)
        for range in SpeedRange.allCases {
            let (from, to) = range.speeds
            guard let reached = track.firstTime(atLeast: to, from: index - 1, through: last) else { continue }
            let began = from <= 0 ? start : track.firstTime(atLeast: from, from: index - 1, through: last)
            if let began, reached > began { attempt.speedTimes[range] = reached - began }
        }
        if let distance = ground.distance, let zero = distance.value(at: start),
            let clock = ground.time(atDistance: zero + options.rollout, from: start, until: end)
        {
            let rolled = zero + options.rollout
            for mark in DragDistance.allCases {
                guard let at = ground.time(atDistance: rolled + mark.metres, from: clock, until: end) else { continue }
                attempt.distanceTimes[mark] = at - clock
                if mark.hasTrap,
                    let entered = ground.time(
                        atDistance: rolled + mark.metres - options.trapLength, from: clock, until: end),
                    at > entered
                {
                    attempt.trapSpeeds[mark] = options.trapLength / (at - entered)
                }
            }
        }
        attempt.slope = ground.slope(from: start, to: end)
        // A start that never got to walking-pace-and-beyond is not an attempt.
        let reachedAnything =
            attempt.speedTimes[.zeroToThirtyMph] != nil || attempt.speedTimes[.zeroToFiftyKmh] != nil
            || attempt.distanceTimes[.sixtyFeet] != nil
        return (reachedAnything ? attempt : nil, last + 1)
    }

    // MARK: - Stops

    static func stops(from braking: BrakingSpeed, track: SpeedTrack, ground: Ground, options: Options) -> [Stop] {
        guard let distance = ground.distance else { return [] }
        let values = track.values
        let target = braking.metresPerSecond
        var stops: [Stop] = []
        var index = 1
        while index < values.count {
            guard values[index - 1] >= target, values[index] < target else {
                index += 1
                continue
            }
            let start = track.crossing(downward: target, between: index - 1, and: index)
            var lowest = values[index]
            var at = index
            var stopped: Double?
            if values[index] < options.movingSpeed {
                stopped = track.crossing(downward: options.movingSpeed, between: index - 1, and: index)
            }
            while stopped == nil, at + 1 < values.count {
                let next = values[at + 1]
                if next > lowest + options.stopRise { break }
                lowest = min(lowest, next)
                at += 1
                if next < options.movingSpeed {
                    // Standing still: the crossing of the moving speed, taken on to zero.
                    let crossing = track.crossing(downward: options.movingSpeed, between: at - 1, and: at)
                    let decel = -track.slope(between: at - 1, and: at)
                    stopped = decel > 0 ? crossing + options.movingSpeed / decel : crossing
                }
            }
            if let stopped, let from = distance.value(at: start), let to = distance.value(at: stopped) {
                var stop = Stop(from: braking, start: start, end: stopped, metres: to - from)
                stop.slope = ground.slope(from: start, to: stopped)
                stops.append(stop)
            }
            index = at + 1
        }
        return stops
    }

    // MARK: - The arithmetic the measures share

    /// The speed channel.
    struct SpeedTrack {
        let times: [Double]
        let values: [Double]

        init(speed: Channel) {
            times = speed.times
            values = speed.values
        }

        func slope(between a: Int, and b: Int) -> Double {
            let dt = times[b] - times[a]
            return dt > 0 ? (values[b] - values[a]) / dt : 0
        }

        func crossing(upward level: Double, between a: Int, and b: Int) -> Double {
            let span = values[b] - values[a]
            let fraction = span > 0 ? (level - values[a]) / span : 0
            return times[a] + (times[b] - times[a]) * fraction
        }

        func crossing(downward level: Double, between a: Int, and b: Int) -> Double {
            let span = values[a] - values[b]
            let fraction = span > 0 ? (values[a] - level) / span : 0
            return times[a] + (times[b] - times[a]) * fraction
        }

        /// The first time speed reaches `level` from sample `first` to `last`, interpolated.
        func firstTime(atLeast level: Double, from first: Int, through last: Int) -> Double? {
            guard first < last else { return nil }
            for index in (first + 1)...last where values[index] >= level {
                if values[index - 1] >= level { return times[index - 1] }
                return crossing(upward: level, between: index - 1, and: index)
            }
            return nil
        }
    }

    /// Distance and altitude, and the speed to interpolate distance with.
    struct Ground {
        let distance: Channel?
        let altitude: Channel?
        let speed: Channel?

        /// The first time the distance reaches `target` between `from` and `until`.
        ///
        /// Between two samples the car accelerates from one speed to the other, so distance is
        /// a curve, not a line: at walking pace, where the rollout is crossed, a straight line
        /// is milliseconds out at 10 Hz and tenths at 1 Hz. With the speed at both ends the curve
        /// is solved instead, which is exact under a constant acceleration; without speed, a line.
        func time(atDistance target: Double, from: Double, until: Double) -> Double? {
            guard let distance else { return nil }
            let times = distance.times
            let values = distance.values
            guard let first = times.firstIndex(where: { $0 > from }) else { return nil }
            var index = max(first, 1)
            while index < times.count, times[index - 1] <= until {
                if values[index] >= target, values[index - 1] < target {
                    let time = crossing(target, between: index - 1, and: index, in: distance)
                    return time <= until ? max(time, from) : nil
                }
                index += 1
            }
            return nil
        }

        private func crossing(_ target: Double, between a: Int, and b: Int, in distance: Channel) -> Double {
            let t0 = distance.times[a]
            let dt = distance.times[b] - t0
            let gap = target - distance.values[a]
            let span = distance.values[b] - distance.values[a]
            let linear = t0 + dt * (span > 0 ? gap / span : 0)
            guard dt > 0, let speed, let v0 = speed.value(at: t0), let v1 = speed.value(at: t0 + dt) else {
                return linear
            }
            // gap = v0·τ + accel·τ²/2, for τ in [0, dt].
            let accel = (v1 - v0) / dt
            let tau: Double
            if abs(accel) < 1e-9 {
                guard v0 > 0 else { return linear }
                tau = gap / v0
            } else {
                let discriminant = v0 * v0 + 2 * accel * gap
                guard discriminant >= 0 else { return linear }
                tau = (-v0 + discriminant.squareRoot()) / accel
            }
            return tau >= 0 && tau <= dt ? t0 + tau : linear
        }

        /// Rise over run between two moments; `nil` without altitude, or over under a metre.
        func slope(from start: Double, to end: Double) -> Double? {
            guard let distance, let altitude, let h0 = altitude.value(at: start), let h1 = altitude.value(at: end),
                let d0 = distance.value(at: start), let d1 = distance.value(at: end), d1 - d0 > 1
            else { return nil }
            return (h1 - h0) / (d1 - d0)
        }
    }
}
