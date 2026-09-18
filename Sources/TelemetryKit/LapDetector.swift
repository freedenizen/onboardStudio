import Foundation

/// A start/finish (or sector) line defined by a point and the direction of travel across it.
public struct FinishLine: Sendable, Hashable, Codable {
    public var latitude: Double
    public var longitude: Double
    /// Direction of travel when crossing, degrees (0 = north). `nil` accepts any direction.
    public var headingDegrees: Double?
    /// Half-width of the line in meters: crossings farther than this from the point are ignored.
    public var halfWidthMeters: Double
    /// Crossings whose heading differs from `headingDegrees` by more than this are ignored.
    public var headingToleranceDegrees: Double

    public init(
        latitude: Double,
        longitude: Double,
        headingDegrees: Double? = nil,
        halfWidthMeters: Double = 25,
        headingToleranceDegrees: Double = 60
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.headingDegrees = headingDegrees
        self.halfWidthMeters = halfWidthMeters
        self.headingToleranceDegrees = headingToleranceDegrees
    }
}

/// Finds laps by detecting when the GPS track crosses a finish line, with sub-sample timing.
public enum LapDetector {
    public struct Crossing: Sendable, Equatable {
        /// Interpolated time of the crossing (session seconds).
        public let time: Double
        public let headingDegrees: Double
    }

    /// Crossing times of `line` in chronological order. The line is the segment perpendicular
    /// to `headingDegrees` (or to the local track direction when heading is nil) through the point.
    public static func crossings(latitude: Channel, longitude: Channel, line: FinishLine) -> [Crossing] {
        guard latitude.count > 1 else { return [] }
        // Local flat projection around the line point (meters).
        let cosLat = cos(line.latitude * .pi / 180)
        func project(_ lat: Double, _ lon: Double) -> (x: Double, y: Double) {
            ((lon - line.longitude) * cosLat * 111_320, (lat - line.latitude) * 110_540)
        }
        var result: [Crossing] = []
        var previous = project(latitude.values[0], longitude.value(at: latitude.times[0]) ?? longitude.values[0])
        for index in 1..<latitude.count {
            let t0 = latitude.times[index - 1]
            let t1 = latitude.times[index]
            let current = project(latitude.values[index], longitude.value(at: t1) ?? longitude.values[index])
            defer { previous = current }
            let dx = current.x - previous.x
            let dy = current.y - previous.y
            let stepLength = (dx * dx + dy * dy).squareRoot()
            guard stepLength > 0 else { continue }
            // Travel heading of this step (0 = north, clockwise).
            let heading = (atan2(dx, dy) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            let lineHeading = line.headingDegrees ?? heading
            if line.headingDegrees != nil {
                var diff = abs(heading - lineHeading).truncatingRemainder(dividingBy: 360)
                if diff > 180 { diff = 360 - diff }
                if diff > line.headingToleranceDegrees { continue }
            }
            // Signed distance of both points along the line's normal (the travel direction).
            let nx = sin(lineHeading * .pi / 180)
            let ny = cos(lineHeading * .pi / 180)
            let d0 = previous.x * nx + previous.y * ny
            let d1 = current.x * nx + current.y * ny
            guard d0 < 0, d1 >= 0 else { continue }
            let fraction = d0 / (d0 - d1)
            // Position on the line at the crossing must be within the half-width.
            let cx = previous.x + dx * fraction
            let cy = previous.y + dy * fraction
            let along = cx * ny - cy * nx
            guard abs(along) <= line.halfWidthMeters else { continue }
            result.append(Crossing(time: t0 + (t1 - t0) * fraction, headingDegrees: heading))
        }
        return result
    }

    /// Builds laps from crossings. `ignoreFirst` crossings are skipped (warm-up passes); the
    /// segment before the first counted crossing becomes an incomplete lap 0, and the segment
    /// after the last one an incomplete final lap.
    public static func laps(from crossings: [Crossing], ignoreFirst: Int, sessionStart: Double, sessionEnd: Double)
        -> [Lap]
    {
        let counted = Array(crossings.dropFirst(max(0, ignoreFirst)))
        guard !counted.isEmpty else {
            return [Lap(number: 0, start: sessionStart, end: sessionEnd, isComplete: false)]
        }
        var laps: [Lap] = []
        if counted[0].time > sessionStart {
            laps.append(Lap(number: 0, start: sessionStart, end: counted[0].time, isComplete: false))
        }
        for index in 0..<counted.count {
            let start = counted[index].time
            let isLast = index == counted.count - 1
            let end = isLast ? sessionEnd : counted[index + 1].time
            laps.append(Lap(number: index + 1, start: start, end: end, isComplete: !isLast))
        }
        return laps
    }

    /// Convenience: detect laps on a session.
    public static func detect(in session: TelemetrySession, line: FinishLine, ignoreFirst: Int = 0) -> [Lap] {
        guard let lat = session[.latitude], let lon = session[.longitude], let range = session.timeRange else {
            return []
        }
        let found = crossings(latitude: lat, longitude: lon, line: line)
        return laps(from: found, ignoreFirst: ignoreFirst, sessionStart: range.lowerBound, sessionEnd: range.upperBound)
    }

    /// The position and heading at `time`, useful for "use the current position as start/finish".
    public static func finishLine(at time: Double, in session: TelemetrySession, halfWidthMeters: Double = 25)
        -> FinishLine?
    {
        let sampler = TelemetrySampler(session: session)
        let sample = sampler.sample(at: time)
        guard let lat = sample[.latitude], let lon = sample[.longitude] else { return nil }
        return FinishLine(
            latitude: lat, longitude: lon, headingDegrees: sample[.heading], halfWidthMeters: halfWidthMeters)
    }
}
