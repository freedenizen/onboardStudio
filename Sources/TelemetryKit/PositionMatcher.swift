import Foundation

/// Matches each point of a reference lap to the nearest point of another lap's line.
///
/// Racelogic's Delta-T is built this way for the same reason: two drivers' lines differ by more
/// than ten metres over a lap, and a differently placed start/finish line adds more, so metre
/// for metre the two laps have drifted apart by the first corner. Matching by place pins every
/// corner to the same piece of tarmac, and gives the offset between the two lines for free.
enum PositionMatcher {
    struct Match {
        /// Distance into the other lap for each point of the reference grid; never decreasing.
        var lapDistances: [Double]
        /// Metres the other lap's line is right (+) or left (−) of the reference's at each point.
        var lateral: [Double]
        /// 1 when the lines ran together, falling as their typical separation approaches the
        /// tolerance.
        var confidence: Double
    }

    /// How far along the other lap, either side of the previous match, the next match is looked
    /// for. Wide enough for a hairpin taken on a very different line; narrow enough that the far
    /// side of a tight circuit cannot steal a match.
    static let searchMeters = 60.0

    /// `nil` when either lap has no position, the other lap does not begin near the reference's
    /// start, or the lines are further apart than `tolerance` at more than a twentieth of the
    /// points — a different circuit, a lap on the other side of a start/finish line, or a lap that
    /// left the track.
    static func match(lap: LapProfile, reference: LapProfile, tolerance: Double) -> Match? {
        guard let origin = reference.position(atDistance: 0),
            let referencePoints = LocalPlane.points(of: reference, origin: origin),
            let lapPoints = LocalPlane.points(of: lap, origin: origin), lapPoints.count >= 3,
            referencePoints.count >= 2, let headings = reference.heading
        else { return nil }
        let line = Line(points: lapPoints, distances: lap.distances, step: lap.stepMeters)
        let window = max(2, Int((searchMeters / lap.stepMeters).rounded()))
        // The other lap should begin near the reference's start. Its line may cross the start
        // just before its own end as well as just after its start — the two lines overlap at
        // the line — so the last quarter is searched too, and a match there counts as just
        // before the start, which a closed lap can run on from.
        let quarter = line.segments / 4
        guard
            let first = line.nearest(to: referencePoints[0], from: 0, to: quarter)
                .flatMap({ $0.distance <= tolerance ? $0 : nil })
                ?? line.nearest(to: referencePoints[0], from: -quarter, to: -1)
        else { return nil }
        var cursor = first.segment
        var lapDistances: [Double] = []
        var lateral: [Double] = []
        var residuals: [Double] = []
        lapDistances.reserveCapacity(referencePoints.count)
        lateral.reserveCapacity(referencePoints.count)
        residuals.reserveCapacity(referencePoints.count)
        var previous = -Double.infinity
        for index in referencePoints.indices {
            let point = referencePoints[index]
            guard let hit = line.nearest(to: point, from: cursor - window, to: cursor + window) else { break }
            cursor = hit.segment
            // The line can wobble back a metre; it cannot run the lap backwards.
            let distance = max(previous, hit.along)
            previous = distance
            lapDistances.append(distance)
            residuals.append(hit.distance)
            // Right of the direction of travel: heading h clockwise from north has the right-hand
            // normal (cos h, −sin h) in east/north.
            let heading = headings[index] * .pi / 180
            let east = hit.point.x - point.x
            let north = hit.point.y - point.y
            lateral.append(east * cos(heading) - north * sin(heading))
        }
        guard lapDistances.count == referencePoints.count else { return nil }
        let outside = residuals.filter { $0 > tolerance }.count
        guard outside * 20 <= residuals.count else { return nil }
        let sorted = residuals.sorted()
        let median = sorted[sorted.count / 2]
        return Match(lapDistances: lapDistances, lateral: lateral, confidence: max(0, 1 - median / tolerance))
    }

    /// The other lap's line, searchable past either end when the lap closes on itself: a
    /// segment index before 0 or after the last is the lap before or after, and its `along`
    /// is offset by a lap length, so a match can run across the start/finish line.
    struct Line {
        let points: [LocalPlane.Point]
        let distances: [Double]
        let step: Double
        let isClosed: Bool

        init(points: [LocalPlane.Point], distances: [Double], step: Double) {
            self.points = points
            self.distances = distances
            self.step = step
            let first = points[0]
            let last = points[points.count - 1]
            let gap = ((first.x - last.x) * (first.x - last.x) + (first.y - last.y) * (first.y - last.y)).squareRoot()
            isClosed = gap < step * 3
        }

        var segments: Int { points.count - 1 }
        var length: Double { distances[distances.count - 1] }

        /// The nearest point to `target` on segments `from...to`, which may run past either end
        /// of a closed lap and are clamped to it otherwise.
        func nearest(to target: LocalPlane.Point, from: Int, to: Int) -> Hit? {
            let lower = isClosed ? from : max(0, from)
            let upper = isClosed ? to : min(segments - 1, to)
            guard lower <= upper else { return nil }
            var best: Hit?
            for index in lower...upper {
                let laps = index >= 0 ? index / segments : -((-index - 1) / segments + 1)
                let segment = index - laps * segments
                let a = points[segment]
                let b = points[segment + 1]
                let dx = b.x - a.x
                let dy = b.y - a.y
                let length2 = dx * dx + dy * dy
                let t = length2 > 0 ? min(1, max(0, ((target.x - a.x) * dx + (target.y - a.y) * dy) / length2)) : 0
                let point = LocalPlane.Point(x: a.x + dx * t, y: a.y + dy * t)
                let dx2 = (point.x - target.x) * (point.x - target.x)
                let dy2 = (point.y - target.y) * (point.y - target.y)
                let distance = (dx2 + dy2).squareRoot()
                if best == nil || distance < (best?.distance ?? .infinity) {
                    let along = distances[segment] + (distances[segment + 1] - distances[segment]) * t
                    best = Hit(
                        segment: index, t: t, point: point, distance: distance, along: along + Double(laps) * length)
                }
            }
            return best
        }
    }

    struct Hit {
        /// Segment index, possibly outside `0..<segments` on a closed lap.
        var segment: Int
        var t: Double
        var point: LocalPlane.Point
        var distance: Double
        /// Distance into the lap, offset by whole laps when the segment wrapped.
        var along: Double
    }
}

/// A lap's positions in metres east and north of a fixed origin: flat enough for a lap.
enum LocalPlane {
    struct Point {
        var x: Double
        var y: Double
    }

    /// Metres per degree of latitude, and of longitude at a latitude; the same constants
    /// `LapDetector` uses, so a gate and a line agree.
    static let metersPerDegreeLatitude = 110_540.0
    static func metersPerDegreeLongitude(at latitude: Double) -> Double { 111_320 * cos(latitude * .pi / 180) }

    /// `profile`'s positions on the plane through `origin`; both laps must use the same one.
    static func points(of profile: LapProfile, origin: (latitude: Double, longitude: Double)) -> [Point]? {
        guard let latitudes = profile.latitude, let longitudes = profile.longitude, !latitudes.isEmpty else {
            return nil
        }
        let perLongitude = metersPerDegreeLongitude(at: origin.latitude)
        return zip(latitudes, longitudes).map { latitude, longitude in
            Point(
                x: (longitude - origin.longitude) * perLongitude,
                y: (latitude - origin.latitude) * metersPerDegreeLatitude)
        }
    }
}
