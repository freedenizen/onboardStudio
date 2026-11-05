import Foundation

/// A circuit as a road, built from one lap's GPS (#413): the centreline every few metres in
/// metres east, north and up of the track's centre, how wide the road is there, where the kerbs
/// are, and the corners — what a 3D view draws, and what a replay needs to put a car *on* the
/// road rather than somewhere near it.
///
/// Nothing here comes from a map. The centreline is the reference lap's own line, the elevation
/// its altitude channel smoothed (GPS altitude wanders by metres), the width the spread of every
/// other lap's line about it, the kerbs the corners `CornerDetector` finds. A circuit the catalogue
/// knows and one it does not build the same way.
public struct TrackModel: Sendable {
    /// Metres east and north of a fixed point: flat enough for a circuit, the same constants
    /// `PositionMatcher` and `LapDetector` use so a gate, a line and a road agree.
    public struct Plane: Sendable, Hashable {
        public let latitude0: Double
        public let longitude0: Double
        /// Metres above sea level that reads as 0 up; the lowest smoothed sample.
        public let altitude0: Double

        public init(latitude0: Double, longitude0: Double, altitude0: Double = 0) {
            self.latitude0 = latitude0
            self.longitude0 = longitude0
            self.altitude0 = altitude0
        }

        public var metersPerDegreeLatitude: Double { LocalPlane.metersPerDegreeLatitude }
        public var metersPerDegreeLongitude: Double { LocalPlane.metersPerDegreeLongitude(at: latitude0) }

        /// (east, north) in metres.
        public func point(latitude: Double, longitude: Double) -> SIMD2<Double> {
            SIMD2(
                (longitude - longitude0) * metersPerDegreeLongitude, (latitude - latitude0) * metersPerDegreeLatitude)
        }

        public func coordinate(at point: SIMD2<Double>) -> (latitude: Double, longitude: Double) {
            (latitude0 + point.y / metersPerDegreeLatitude, longitude0 + point.x / metersPerDegreeLongitude)
        }
    }

    /// One point of the centreline.
    public struct Sample: Sendable, Hashable {
        /// Metres east, north and up of the plane's origin.
        public var position: SIMD3<Double>
        /// Direction of travel, degrees clockwise from north.
        public var heading: Double
        /// Metres from the centreline to either edge of the road.
        public var halfWidth: Double
        public var kerbLeft: Bool
        public var kerbRight: Bool

        public init(position: SIMD3<Double>, heading: Double, halfWidth: Double, kerbLeft: Bool, kerbRight: Bool) {
            self.position = position
            self.heading = heading
            self.halfWidth = halfWidth
            self.kerbLeft = kerbLeft
            self.kerbRight = kerbRight
        }

        /// (east, north) only.
        public var point: SIMD2<Double> { SIMD2(position.x, position.y) }
    }

    public struct Options: Sendable, Hashable {
        /// Metres between centreline samples.
        public var stepMeters: Double = 4
        /// The road's half-width with no other lap to measure it from.
        public var defaultHalfWidth: Double = 6
        /// The narrowest and widest the measured road may be.
        public var halfWidthRange: ClosedRange<Double> = 5...12
        /// Metres added either side of the widest line driven.
        public var widthMargin: Double = 2
        /// Moving average over the measured width, so one wide moment does not bulge the road.
        public var widthSmoothingMeters: Double = 40
        /// Moving average over the altitude; GPS altitude is noisy by metres.
        public var elevationSmoothingMeters: Double = 80
        /// How far from the reference's line another lap may stray and still be the same road.
        public var matchToleranceMeters: Double = 30

        public init() {}
    }

    public let plane: Plane
    public let stepMeters: Double
    public let lengthMeters: Double
    /// The closed loop, start/finish first; the last sample is one step short of the first.
    public let samples: [Sample]
    /// The corners of the reference lap, apex order.
    public let corners: [Corner]
    /// Whether the up axis means anything: the reference lap carried altitude.
    public let hasElevation: Bool
    /// The grid `nearest(to:)` searches: sample indices by 20 m cell.
    private let cells: [SIMD2<Int>: [Int]]
    private static let cellMeters = 20.0

    /// The reference lap's line as the road. `laps` are the other lines driven on it, which set
    /// the width; the reference itself may be among them. `nil` without position.
    public static func make(reference: LapProfile, laps: [LapProfile] = [], options: Options = Options())
        -> TrackModel?
    {
        guard let latitudes = reference.latitude, let longitudes = reference.longitude, reference.count >= 4,
            reference.lengthMeters >= options.stepMeters * 4
        else { return nil }
        let step = max(1, options.stepMeters)
        let count = max(4, Int((reference.lengthMeters / step).rounded(.down)))
        let distances = (0..<count).map { Double($0) * step }
        let plane = Plane(
            latitude0: latitudes.reduce(0, +) / Double(latitudes.count),
            longitude0: longitudes.reduce(0, +) / Double(longitudes.count))
        guard let line = centreline(of: reference, at: distances, on: plane) else { return nil }
        let (ups, altitude0) = elevation(of: reference, at: distances, step: step, options: options)
        let halfWidths = halfWidths(of: reference, laps: laps, at: distances, headings: line.headings, options: options)
        let corners = CornerDetector.corners(of: reference)
        let length = Double(count) * step
        let kerbs = kerbs(for: corners, at: distances, lap: length)
        let samples = (0..<count).map { index in
            Sample(
                position: SIMD3(line.points[index].x, line.points[index].y, ups[index]), heading: line.headings[index],
                halfWidth: halfWidths[index], kerbLeft: kerbs.left[index], kerbRight: kerbs.right[index])
        }
        return TrackModel(
            plane: Plane(latitude0: plane.latitude0, longitude0: plane.longitude0, altitude0: altitude0),
            stepMeters: step, lengthMeters: length, samples: samples, corners: corners,
            hasElevation: reference.has(.altitude))
    }

    /// A road from samples already worked out: what `make` ends with, and what a test or a
    /// mesh builder that lifts the road a little starts from.
    public init(
        plane: Plane, stepMeters: Double, lengthMeters: Double, samples: [Sample], corners: [Corner],
        hasElevation: Bool
    ) {
        self.plane = plane
        self.stepMeters = stepMeters
        self.lengthMeters = lengthMeters
        self.samples = samples
        self.corners = corners
        self.hasElevation = hasElevation
        var cells: [SIMD2<Int>: [Int]] = [:]
        for (index, sample) in samples.enumerated() {
            cells[Self.cell(of: sample.point), default: []].append(index)
        }
        self.cells = cells
    }

    /// The centreline `distance` metres round the lap (wrapping), interpolated between samples.
    public func sample(atDistance distance: Double) -> Sample {
        let count = samples.count
        guard count > 1 else { return samples[0] }
        var wrapped = distance.truncatingRemainder(dividingBy: lengthMeters)
        if wrapped < 0 { wrapped += lengthMeters }
        let lower = min(Int(wrapped / stepMeters), count - 1)
        let upper = (lower + 1) % count
        let fraction = min(max((wrapped - Double(lower) * stepMeters) / stepMeters, 0), 1)
        let a = samples[lower]
        let b = samples[upper]
        var turn = b.heading - a.heading
        if turn > 180 { turn -= 360 }
        if turn < -180 { turn += 360 }
        return Sample(
            position: a.position + (b.position - a.position) * fraction,
            heading: (a.heading + turn * fraction + 360).truncatingRemainder(dividingBy: 360),
            halfWidth: a.halfWidth + (b.halfWidth - a.halfWidth) * fraction, kerbLeft: a.kerbLeft,
            kerbRight: a.kerbRight)
    }

    /// Where on the road a point is: metres round the lap of the nearest piece of centreline, and
    /// metres right (+) or left (−) of it. Searched by cell, so a lap of points costs nothing much.
    public func nearest(to point: SIMD2<Double>) -> (distance: Double, lateral: Double) {
        let home = Self.cell(of: point)
        var nearIndex: Int?
        var nearSquared = Double.infinity
        var reach = 1
        while nearIndex == nil, reach <= 8 {
            for dx in -reach...reach {
                for dy in -reach...reach {
                    for index in cells[SIMD2(home.x + dx, home.y + dy)] ?? [] {
                        let delta = samples[index].point - point
                        let squared = delta.x * delta.x + delta.y * delta.y
                        if squared < nearSquared {
                            nearIndex = index
                            nearSquared = squared
                        }
                    }
                }
            }
            reach += 1
        }
        guard let near = nearIndex else { return (0, 0) }
        // Project onto the better of the two segments touching the nearest sample.
        var best = Foot(distance: Double(near) * stepMeters, lateral: 0, squared: .infinity)
        for start in [(near - 1 + samples.count) % samples.count, near] {
            if let foot = foot(of: point, onSegmentFrom: start), foot.squared < best.squared { best = foot }
        }
        return (best.distance, best.lateral)
    }

    private struct Foot {
        var distance: Double
        var lateral: Double
        var squared: Double
    }

    /// Where `point` falls on the segment from sample `start` to the next: metres round the lap,
    /// metres right (+) or left (−), and how far away squared.
    private func foot(of point: SIMD2<Double>, onSegmentFrom start: Int) -> Foot? {
        let a = samples[start].point
        let b = samples[(start + 1) % samples.count].point
        let segment = b - a
        let lengthSquared = segment.x * segment.x + segment.y * segment.y
        guard lengthSquared > 0 else { return nil }
        let t = min(max(((point - a).x * segment.x + (point - a).y * segment.y) / lengthSquared, 0), 1)
        let offset = point - (a + segment * t)
        let squared = offset.x * offset.x + offset.y * offset.y
        // Right of the direction of travel is positive: the cross product's sign, flipped.
        let lateral = (segment.x * offset.y - segment.y * offset.x) < 0 ? sqrt(squared) : -sqrt(squared)
        return Foot(distance: Double(start) * stepMeters + t * stepMeters, lateral: lateral, squared: squared)
    }

    /// Up at the nearest piece of road to `point`.
    public func elevation(at point: SIMD2<Double>) -> Double {
        sample(atDistance: nearest(to: point).distance).position.z
    }

    // MARK: - Helpers

    private static func cell(of point: SIMD2<Double>) -> SIMD2<Int> {
        SIMD2(Int((point.x / cellMeters).rounded(.down)), Int((point.y / cellMeters).rounded(.down)))
    }
}

// MARK: - Building the road

extension TrackModel {
    /// The reference's position and heading at each distance, on the plane.
    static func centreline(of reference: LapProfile, at distances: [Double], on plane: Plane)
        -> (points: [SIMD2<Double>], headings: [Double])?
    {
        var points: [SIMD2<Double>] = []
        var headings: [Double] = []
        points.reserveCapacity(distances.count)
        headings.reserveCapacity(distances.count)
        for distance in distances {
            guard let position = reference.position(atDistance: distance) else { return nil }
            points.append(plane.point(latitude: position.latitude, longitude: position.longitude))
            headings.append(reference.heading(atDistance: distance) ?? 0)
        }
        return (points, headings)
    }

    /// Up at each distance: the altitude channel smoothed round the loop, levelled so the lap
    /// closes, lifted so the lowest point is 0; all 0 without altitude. Also the altitude that 0 is.
    static func elevation(of reference: LapProfile, at distances: [Double], step: Double, options: Options)
        -> (ups: [Double], altitude0: Double)
    {
        guard reference.has(.altitude) else { return ([Double](repeating: 0, count: distances.count), 0) }
        let raw = distances.map { reference.value(of: .altitude, atDistance: $0) ?? 0 }
        var smoothed = circularMovingAverage(raw, window: Int((options.elevationSmoothingMeters / step).rounded()))
        let count = smoothed.count
        if let first = smoothed.first, let last = smoothed.last, count > 1 {
            let drift = last - first
            for index in smoothed.indices { smoothed[index] -= drift * Double(index) / Double(count - 1) }
        }
        let altitude0 = smoothed.min() ?? 0
        return (smoothed.map { $0 - altitude0 }, altitude0)
    }

    /// The road's half-width at each distance: the widest any other line strays from the
    /// reference, with a margin, smoothed, and never wider than the bend allows.
    static func halfWidths(
        of reference: LapProfile, laps: [LapProfile], at distances: [Double], headings: [Double], options: Options
    ) -> [Double] {
        let count = distances.count
        let step = distances.count > 1 ? distances[1] - distances[0] : options.stepMeters
        var spread = [Double](repeating: 0, count: count)
        var measured = false
        for lap in laps {
            guard
                let match = PositionMatcher.match(
                    lap: lap, reference: reference, tolerance: options.matchToleranceMeters)
            else { continue }
            measured = true
            for (index, distance) in distances.enumerated() {
                let gridIndex = min(match.lateral.count - 1, Int((distance / reference.stepMeters).rounded()))
                if gridIndex >= 0 { spread[index] = max(spread[index], abs(match.lateral[gridIndex])) }
            }
        }
        var halfWidths = [Double](repeating: options.defaultHalfWidth, count: count)
        if measured {
            let range = options.halfWidthRange
            halfWidths = circularMovingAverage(
                spread.map { min(max($0 + options.widthMargin, range.lowerBound), range.upperBound) },
                window: Int((options.widthSmoothingMeters / step).rounded()))
        }
        for index in halfWidths.indices {
            // A ribbon wider than the bend's radius folds over itself on the inside.
            var turn = abs(headings[(index + 1) % count] - headings[index])
            if turn > 180 { turn = 360 - turn }
            let radius = turn > 0.01 ? step / (turn * .pi / 180) : .infinity
            halfWidths[index] = min(halfWidths[index], max(2, radius * 0.8))
        }
        return halfWidths
    }

    /// Kerbs at each distance: the inside of a corner from entry to apex, the outside from apex
    /// to exit.
    static func kerbs(for corners: [Corner], at distances: [Double], lap: Double) -> (left: [Bool], right: [Bool]) {
        var left = [Bool](repeating: false, count: distances.count)
        var right = [Bool](repeating: false, count: distances.count)
        for corner in corners {
            for (index, distance) in distances.enumerated() {
                if within(distance, from: corner.startDistance, to: corner.apexDistance, lap: lap) {
                    if corner.turnsRight { right[index] = true } else { left[index] = true }
                }
                if within(distance, from: corner.apexDistance, to: corner.endDistance, lap: lap) {
                    if corner.turnsRight { left[index] = true } else { right[index] = true }
                }
            }
        }
        return (left, right)
    }

    /// Whether `distance` lies on the way round from `from` to `to`, which may cross the line.
    static func within(_ distance: Double, from: Double, to: Double, lap: Double) -> Bool {
        if from <= to { return distance >= from && distance <= to }
        return distance >= from || distance <= to
    }

    /// A moving average that wraps round the loop, so the start/finish is no seam.
    static func circularMovingAverage(_ values: [Double], window: Int) -> [Double] {
        let count = values.count
        guard count > 0, window > 1 else { return values }
        let half = min(window / 2, count / 2)
        return (0..<count).map { index in
            var sum = 0.0
            for offset in -half...half { sum += values[((index + offset) % count + count) % count] }
            return sum / Double(2 * half + 1)
        }
    }
}
