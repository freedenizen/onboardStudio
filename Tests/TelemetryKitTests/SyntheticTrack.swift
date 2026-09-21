import Foundation

@testable import TelemetryKit

/// A circuit with corners in known places, so corner detection and sector boundaries can be
/// checked against arithmetic rather than against a recording.
///
/// The shape is a stadium: a bottom straight, a 180° right-hand bend, a top straight, and a
/// second 180° right-hand bend back to the start. The start/finish sits in the middle of the
/// bottom straight, where a circuit puts it, so neither bend straddles it.
enum SyntheticTrack {
    /// Where the corners are, in metres into the lap, for `straight` and `radius`.
    struct Geometry {
        let straight: Double
        let radius: Double

        var bendLength: Double { .pi * radius }
        var lapLength: Double { 2 * straight + 2 * bendLength }
        /// First bend: leaves the bottom straight and returns on the top one.
        var firstBend: ClosedRange<Double> { (straight / 2)...(straight / 2 + bendLength) }
        var secondBend: ClosedRange<Double> {
            (1.5 * straight + bendLength)...(1.5 * straight + 2 * bendLength)
        }
        /// The one straight that does not hold the start/finish line.
        var backStraightMidpoint: Double { (firstBend.upperBound + secondBend.lowerBound) / 2 }
    }

    static let origin = (latitude: 37.5, longitude: -122.0)

    /// Position `travelled` metres into a lap, in metres east and north of `origin`.
    static func point(at travelled: Double, geometry g: Geometry) -> (x: Double, y: Double) {
        let s = travelled.truncatingRemainder(dividingBy: g.lapLength)
        let half = g.straight / 2
        if s < half { return (s, 0) }  // bottom straight, heading east
        if s < half + g.bendLength {  // right-hand bend, clockwise about (half, -radius)
            let phi = (s - half) / g.radius
            return (half + g.radius * sin(phi), -g.radius + g.radius * cos(phi))
        }
        if s < 1.5 * g.straight + g.bendLength {  // top straight, heading west
            return (half - (s - half - g.bendLength), -2 * g.radius)
        }
        if s < g.secondBend.upperBound {  // second bend, back onto the bottom straight
            let psi = (s - g.secondBend.lowerBound) / g.radius
            return (half - g.straight - g.radius * sin(psi), -g.radius - g.radius * cos(psi))
        }
        // The rest of the bottom straight, heading east back to the start/finish line.
        return (half - g.straight + (s - g.secondBend.upperBound), 0)
    }

    /// A session driving `laps` laps at `speed` m/s, sampled every `step` metres.
    ///
    /// `lapSpeeds` scales each lap's speed, which is how a test makes one lap quicker in one
    /// sector without changing where the track goes.
    static func session(
        straight: Double = 400,
        radius: Double = 60,
        speed: Double = 25,
        laps lapCount: Int = 3,
        step: Double = 2,
        /// Mirrors the circuit north–south, which turns the right-handers into left-handers
        /// without moving a single distance.
        mirrored: Bool = false,
        speedInSector: (_ lap: Int, _ distanceIntoLap: Double) -> Double = { _, _ in 1 }
    ) -> TelemetrySession {
        let g = Geometry(straight: straight, radius: radius)
        // A whole number of samples per lap, so every lap is exactly one lap long and the lap
        // boundaries land on samples rather than drifting a few metres per lap.
        let perLap = Int((g.lapLength / step).rounded())
        let spacing = g.lapLength / Double(perLap)
        var times: [Double] = []
        var latitudes: [Double] = []
        var longitudes: [Double] = []
        var distances: [Double] = []
        var starts: [Double] = []
        var now = 0.0
        let flip = mirrored ? -1.0 : 1.0
        let metersPerDegreeEast = 111_320 * cos(origin.latitude * .pi / 180)

        func emit(_ into: Double, lap: Int) {
            let point = point(at: into, geometry: g)
            times.append(now)
            latitudes.append(origin.latitude + flip * point.y / 110_540)
            longitudes.append(origin.longitude + point.x / metersPerDegreeEast)
            distances.append(Double(lap) * g.lapLength + into)
        }

        for lap in 0..<lapCount {
            starts.append(now)
            for index in 0..<perLap {
                let into = Double(index) * spacing
                emit(into, lap: lap)
                now += spacing / (speed * speedInSector(lap, into))
            }
        }
        // One last sample closing the final lap on the start/finish line.
        emit(0, lap: lapCount)

        let closed = starts.enumerated().map { index, start in
            Lap(
                number: index + 1, start: start,
                end: index + 1 < starts.count ? starts[index + 1] : now, isComplete: true)
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(role: .latitude, name: "lat", unit: .degrees, times: times, values: latitudes),
                Channel(role: .longitude, name: "lon", unit: .degrees, times: times, values: longitudes),
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distances),
            ],
            laps: closed)
    }

    static func geometry(straight: Double = 400, radius: Double = 60) -> Geometry {
        Geometry(straight: straight, radius: radius)
    }
}
