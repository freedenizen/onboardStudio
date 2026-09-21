import Foundation

/// A stretch of a lap where the track turns consistently one way.
///
/// Distances are metres into the lap, so a corner found on one lap names the same piece of
/// tarmac on every other lap of the same session.
public struct Corner: Sendable, Equatable {
    public let startDistance: Double
    public let endDistance: Double
    /// The tightest point of the turn — where a circuit diagram would put the apex.
    public let apexDistance: Double
    /// Total heading change through the corner in degrees; positive turns right (clockwise).
    public let headingChangeDegrees: Double

    public init(startDistance: Double, endDistance: Double, apexDistance: Double, headingChangeDegrees: Double) {
        self.startDistance = startDistance
        self.endDistance = endDistance
        self.apexDistance = apexDistance
        self.headingChangeDegrees = headingChangeDegrees
    }

    public var turnsRight: Bool { headingChangeDegrees > 0 }
    public var lengthMeters: Double { endDistance - startDistance }
}

/// Finds the corners of a lap from the curvature of its GPS trace.
///
/// Used to keep a sector boundary off a corner (`SectorMode.cornerAware`) and to number the
/// corners on the track map. Nothing here knows the circuit: the only input is where the car
/// went, so it works on an unmapped venue and on an autocross.
public enum CornerDetector {
    public struct Options: Sendable, Hashable {
        /// The trace is resampled to this spacing before curvature is measured, which makes the
        /// result independent of the logger's sample rate.
        public var stepMeters: Double
        /// Curvature is averaged over this much track. Without it GPS noise makes every straight
        /// a series of tiny corners.
        public var smoothingMeters: Double
        /// A turn tighter than this radius counts as a corner. 250 m keeps a motorway-speed kink
        /// out and a fast sweeper in.
        public var cornerRadiusMeters: Double
        /// Turns the same way separated by less track than this are one corner, so an esses is
        /// not reported as four.
        public var minStraightMeters: Double
        /// A corner must turn at least this much in total, which drops lane changes and wander.
        public var minTurnDegrees: Double

        public init(
            stepMeters: Double = 5,
            smoothingMeters: Double = 25,
            cornerRadiusMeters: Double = 250,
            minStraightMeters: Double = 40,
            minTurnDegrees: Double = 25
        ) {
            self.stepMeters = max(1, stepMeters)
            self.smoothingMeters = max(0, smoothingMeters)
            self.cornerRadiusMeters = max(1, cornerRadiusMeters)
            self.minStraightMeters = max(0, minStraightMeters)
            self.minTurnDegrees = max(0, minTurnDegrees)
        }

        /// Curvature at which a turn becomes a corner, in degrees per metre.
        var curvatureThreshold: Double { (180 / .pi) / cornerRadiusMeters }
    }

    /// The corners of `lap`, in the order they are driven.
    public static func corners(of lap: Lap, in session: TelemetrySession, options: Options = Options()) -> [Corner] {
        guard let path = Path(lap: lap, session: session, step: options.stepMeters) else { return [] }
        return corners(along: path, options: options)
    }

    // MARK: - The trace, resampled to a fixed distance step

    /// A lap's positions at a uniform spacing, which is what makes curvature comparable between
    /// a slow corner sampled densely and a straight sampled sparsely.
    struct Path {
        /// Distance into the lap of each point, `0, step, 2 * step, …`.
        let distances: [Double]
        let latitude: [Double]
        let longitude: [Double]
        let step: Double

        init?(lap: Lap, session: TelemetrySession, step: Double) {
            guard let latChannel = session[.latitude], let lonChannel = session[.longitude],
                let distanceChannel = session[.distance], let end = lap.end, end > lap.start,
                let startDistance = distanceChannel.value(at: lap.start),
                let endDistance = distanceChannel.value(at: end)
            else { return nil }
            let length = endDistance - startDistance
            guard length > step * 4 else { return nil }
            var distances: [Double] = []
            var latitudes: [Double] = []
            var longitudes: [Double] = []
            var travelled = 0.0
            while travelled <= length {
                guard
                    let time = LapComparison.time(
                        atDistance: startDistance + travelled, in: distanceChannel, between: lap.start, and: end),
                    let lat = latChannel.value(at: time), let lon = lonChannel.value(at: time)
                else { break }
                distances.append(travelled)
                latitudes.append(lat)
                longitudes.append(lon)
                travelled += step
            }
            guard distances.count >= 4 else { return nil }
            self.distances = distances
            self.latitude = latitudes
            self.longitude = longitudes
            self.step = step
        }

        var count: Int { distances.count }
        var length: Double { distances[distances.count - 1] }
    }

    /// Signed heading change per metre at each point of `path`, positive clockwise. The first and
    /// last entries are zero because a turn needs a step either side of it.
    static func curvature(along path: Path) -> [Double] {
        var headings: [Double] = []
        headings.reserveCapacity(path.count - 1)
        for index in 0..<(path.count - 1) {
            headings.append(
                DerivedChannels.bearing(
                    lat1: path.latitude[index], lon1: path.longitude[index],
                    lat2: path.latitude[index + 1], lon2: path.longitude[index + 1]))
        }
        var result = [Double](repeating: 0, count: path.count)
        guard headings.count >= 2 else { return result }
        for index in 1..<headings.count {
            result[index] = signedDifference(headings[index], headings[index - 1]) / path.step
        }
        return result
    }

    /// `a − b` folded into −180…180, so crossing north does not read as a 359° turn.
    static func signedDifference(_ a: Double, _ b: Double) -> Double {
        var diff = (a - b).truncatingRemainder(dividingBy: 360)
        if diff > 180 { diff -= 360 }
        if diff < -180 { diff += 360 }
        return diff
    }

    /// Centred moving average over `window` samples either side.
    static func smoothed(_ values: [Double], window: Int) -> [Double] {
        guard window > 0, values.count > 2 * window else { return values }
        var prefix = [Double](repeating: 0, count: values.count + 1)
        for index in values.indices { prefix[index + 1] = prefix[index] + values[index] }
        return values.indices.map { index in
            let lower = max(0, index - window)
            let upper = min(values.count, index + window + 1)
            return (prefix[upper] - prefix[lower]) / Double(upper - lower)
        }
    }

    // MARK: - Runs of curvature

    /// A stretch of the path curving the same way, as indices into the resampled trace.
    struct Run {
        var lower: Int
        var upper: Int
        let sign: Double
    }

    static func corners(along path: Path, options: Options) -> [Corner] {
        let raw = curvature(along: path)
        let window = Int((options.smoothingMeters / options.stepMeters / 2).rounded())
        let smooth = smoothed(raw, window: window)
        let threshold = options.curvatureThreshold

        // Maximal runs of the same-signed curvature above the threshold.
        var runs: [Run] = []
        var index = 0
        while index < smooth.count {
            let value = smooth[index]
            guard abs(value) >= threshold else {
                index += 1
                continue
            }
            let sign = value < 0 ? -1.0 : 1.0
            var upper = index
            while upper + 1 < smooth.count, abs(smooth[upper + 1]) >= threshold,
                (smooth[upper + 1] < 0 ? -1.0 : 1.0) == sign
            {
                upper += 1
            }
            runs.append(Run(lower: index, upper: upper, sign: sign))
            index = upper + 1
        }

        // A short straight between two turns the same way is part of one corner, not a gap.
        var merged: [Run] = []
        for run in runs {
            if var last = merged.last, last.sign == run.sign,
                path.distances[run.lower] - path.distances[last.upper] < options.minStraightMeters
            {
                last.upper = run.upper
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }

        return merged.compactMap { run in
            let change = (run.lower...run.upper).reduce(0.0) { $0 + raw[$1] * path.step }
            guard abs(change) >= options.minTurnDegrees else { return nil }
            let apex = (run.lower...run.upper).max { abs(smooth[$0]) < abs(smooth[$1]) } ?? run.lower
            return Corner(
                startDistance: path.distances[run.lower], endDistance: path.distances[run.upper],
                apexDistance: path.distances[apex], headingChangeDegrees: change)
        }
    }

    /// Midpoints of the straights *between* corners, which is where a sector boundary belongs.
    ///
    /// The pit straight is deliberately absent: it holds the start/finish line, and a sector
    /// boundary a few metres from it would time a sector nobody drives.
    public static func straightMidpoints(between corners: [Corner]) -> [Double] {
        guard corners.count > 1 else { return [] }
        return (0..<(corners.count - 1)).map { index in
            (corners[index].endDistance + corners[index + 1].startDistance) / 2
        }
    }
}
