import Foundation

/// A stretch where another car's log puts it close ahead (#574): it passed the place this car
/// was at a moment ago, less than a following gap before. Measured, not inferred, but still not a
/// verdict: a driver may sit behind a friend on purpose, so it becomes a suggestion like the
/// telemetry's (#572), never a mark.
public struct CarAhead: Sendable, Hashable, Codable {
    /// What the other car is called: the Logbook's name for it, else its file's.
    public var car: String
    /// The stretch, in this session's time.
    public var window: LapProfile.Window
    /// The closest the other car was ahead in the stretch, seconds.
    public var closestGap: Double

    public init(car: String, window: LapProfile.Window, closestGap: Double) {
        self.car = car
        self.window = window
        self.closestGap = closestGap
    }
}

/// Reads two sessions recorded on the same clock at the same circuit for when one car followed
/// the other. At each moment the gap is how long ago the other car passed the place this one is
/// at: its trace is searched over the last `followingSeconds` for the point nearest this car's,
/// so a lapped car counts as much as one racing for position, and a car on the other side of the
/// circuit, or in the pit lane, never does.
public enum CarsAhead {
    public struct Options: Sendable, Hashable {
        /// Closer than this behind another car is following it, seconds.
        public var followingSeconds: Double
        /// A stretch shorter than this is a pass, not following, seconds.
        public var minimumSeconds: Double
        /// The other car's line must come this close to this car's position to be the same
        /// place: the width of a line through a corner and GPS's own error, metres.
        public var samePlaceMeters: Double
        /// Slower than this is the pit lane or the grid, where cars queue: m/s.
        public var minimumSpeed: Double
        /// How often the gap is read, seconds.
        public var step: Double

        public init(
            followingSeconds: Double = 1.5, minimumSeconds: Double = 2, samePlaceMeters: Double = 12,
            minimumSpeed: Double = 8, step: Double = 0.2
        ) {
            self.followingSeconds = max(0.1, followingSeconds)
            self.minimumSeconds = max(0, minimumSeconds)
            self.samePlaceMeters = max(1, samePlaceMeters)
            self.minimumSpeed = max(0, minimumSpeed)
            self.step = max(0.02, step)
        }
    }

    /// The stretches of `session` spent close behind `other`; empty when either lacks a position
    /// or a place on the clock, or the two never overlap.
    public static func following(
        in session: TelemetrySession, behind other: TelemetrySession, car: String, options: Options = Options()
    ) -> [CarAhead] {
        guard let mine = Trace(session), let theirs = Trace(other), let range = session.timeRange,
            let offset = clockOffset(from: session, to: other)
        else { return [] }
        var times: [Double] = []
        var gaps: [Double?] = []
        var time = range.lowerBound
        while time <= range.upperBound {
            times.append(time)
            gaps.append(gap(at: time, mine: mine, theirs: theirs, offset: offset, options: options))
            time += options.step
        }
        let bridge = Int((1 / options.step).rounded())
        return TrafficSuggestions.runs(of: gaps.map { $0 != nil }, bridging: bridge).compactMap { run in
            let start = times[run.lowerBound]
            let end = times[run.upperBound]
            guard end - start >= options.minimumSeconds else { return nil }
            let closest = gaps[run].compactMap { $0 }.min() ?? options.followingSeconds
            return CarAhead(car: car, window: LapProfile.Window(start: start, end: end), closestGap: closest)
        }
    }

    /// What to add to a time in `session` to get the same moment in `other`'s time.
    static func clockOffset(from session: TelemetrySession, to other: TelemetrySession) -> Double? {
        guard let epoch = session.epoch(forSessionTime: 0), let there = other.sessionTime(forEpoch: epoch) else {
            return nil
        }
        return there
    }

    /// How long ago `theirs` passed the place `mine` is at `time`, when that is within the
    /// following gap; `nil` when it is not, or this car is barely moving.
    static func gap(at time: Double, mine: Trace, theirs: Trace, offset: Double, options: Options) -> Double? {
        let here = mine.point(at: time)
        guard here.distance(to: mine.point(at: time - 1)) >= options.minimumSpeed else { return nil }
        let now = time + offset
        let from = now - options.followingSeconds
        guard let first = theirs.firstIndex(atOrAfter: from), first > 0, now <= theirs.times.last ?? -.infinity
        else { return nil }
        var best: (distance: Double, time: Double)?
        var index = first
        while index < theirs.times.count, theirs.times[index - 1] <= now {
            let a = theirs.points[index - 1]
            let b = theirs.points[index]
            let (fraction, distance) = here.nearest(onSegmentFrom: a, to: b)
            let at = theirs.times[index - 1] + fraction * (theirs.times[index] - theirs.times[index - 1])
            if from...now ~= at, distance < (best?.distance ?? .infinity) { best = (distance, at) }
            index += 1
        }
        // Closer than a car's length is alongside, passing or being passed, or the same recording
        // read twice: not a car ahead.
        guard let best, best.distance <= options.samePlaceMeters, now - best.time >= 0.2 else { return nil }
        return now - best.time
    }

    /// A session's positions in metres on one plane, shared by every session (the plane is
    /// centred on a fixed point for the latitude, so two cars' traces agree).
    struct Trace {
        var times: [Double]
        var points: [Point]

        init?(_ session: TelemetrySession) {
            guard let latitudes = session[.latitude], let longitudes = session[.longitude],
                let latitude = latitudes.values.first(where: { $0 != 0 }), !latitudes.times.isEmpty
            else { return nil }
            // Rounded, so two sessions at one circuit share the plane.
            let origin = (latitude * 10).rounded() / 10
            let perLongitude = LocalPlane.metersPerDegreeLongitude(at: origin)
            times = latitudes.times
            points = zip(latitudes.times, latitudes.values).map { time, latitude in
                Point(
                    x: (longitudes.value(at: time) ?? 0) * perLongitude,
                    y: (latitude - origin) * LocalPlane.metersPerDegreeLatitude)
            }
        }

        func firstIndex(atOrAfter time: Double) -> Int? {
            let index = times.firstIndex(atOrAfter: time)
            return index < times.count ? index : nil
        }

        func point(at time: Double) -> Point {
            let upper = min(max(times.firstIndex(atOrAfter: time), 1), times.count - 1)
            let lower = upper - 1
            guard upper > lower, times[upper] > times[lower] else { return points[upper] }
            let fraction = min(max((time - times[lower]) / (times[upper] - times[lower]), 0), 1)
            return Point(
                x: points[lower].x + (points[upper].x - points[lower].x) * fraction,
                y: points[lower].y + (points[upper].y - points[lower].y) * fraction)
        }
    }

    struct Point {
        var x: Double
        var y: Double

        func distance(to other: Point) -> Double {
            ((x - other.x) * (x - other.x) + (y - other.y) * (y - other.y)).squareRoot()
        }

        /// The nearest point to this one on the segment `a`–`b`: how far along it, 0–1, and how far away.
        func nearest(onSegmentFrom a: Point, to b: Point) -> (Double, Double) {
            let dx = b.x - a.x
            let dy = b.y - a.y
            let length = dx * dx + dy * dy
            let fraction = length > 0 ? min(max(((x - a.x) * dx + (y - a.y) * dy) / length, 0), 1) : 0
            return (fraction, distance(to: Point(x: a.x + dx * fraction, y: a.y + dy * fraction)))
        }
    }
}
