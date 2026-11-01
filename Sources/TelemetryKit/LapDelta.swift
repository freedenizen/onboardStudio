import Foundation

/// How two laps are lined up before they are compared.
public enum LapAlignment: Sendable, Hashable, Codable {
    /// Metre for metre from the start of each lap. Right when both laps follow the same line,
    /// which two laps of one session do to about a metre; it is what sectors and the delta
    /// channels use.
    case distance
    /// By fraction of the lap: a lap 1 % longer than the reference is squeezed by 1 %, so a
    /// corner at three quarters distance still meets a corner at three quarters distance. What
    /// `LapTimeWarp` does to keep two pictures level, and the fallback when two laps of different
    /// length have to be compared without positions.
    case fractionOfLap
}

/// Where one lap gained and lost time against another, along the reference lap.
///
/// Positive is behind. The trace is on the reference's grid, so `delta(atDistance:)` takes a
/// distance into the *reference* lap, which is also where the corners are measured.
public struct LapDeltaTrace: Sendable {
    /// Distances into the reference lap, its grid.
    public let distances: [Double]
    /// Seconds the lap is behind (+) or ahead of (−) the reference at each grid point.
    public let delta: [Double]
    /// Metres per second the lap is faster (+) or slower (−) than the reference at each grid
    /// point; `nil` when either profile has no speed.
    public let speedDelta: [Double]?
    public let alignment: LapAlignment
    /// How far to trust a metre-for-metre reading: 1 when the two laps are the same length to
    /// within 2 %, falling to 0 as the difference reaches 10 % (by distance) or 20 % (by fraction).
    /// A guide to how much of a "brake point 8 m earlier" is real, not a measurement.
    public let confidence: Double

    /// `nil` when either profile is empty.
    public init?(lap: LapProfile, reference: LapProfile, alignment: LapAlignment = .distance) {
        guard lap.count >= 2, reference.count >= 2, reference.lengthMeters > 0 else { return nil }
        let ratio = lap.lengthMeters / reference.lengthMeters
        let lapDistance: (Double) -> Double
        switch alignment {
        case .distance: lapDistance = { $0 }
        case .fractionOfLap: lapDistance = { $0 * ratio }
        }
        distances = reference.distances
        delta = zip(reference.distances, reference.elapsed).map { distance, elapsed in
            lap.elapsed(atDistance: lapDistance(distance)) - elapsed
        }
        if let lapSpeed = lap.channels[.speed], let referenceSpeed = reference.channels[.speed], !lapSpeed.isEmpty {
            speedDelta = zip(reference.distances, referenceSpeed).map { distance, speed in
                (lap.value(of: .speed, atDistance: lapDistance(distance)) ?? 0) - speed
            }
        } else {
            speedDelta = nil
        }
        self.alignment = alignment
        let difference = abs(ratio - 1)
        switch alignment {
        case .distance: confidence = max(0, 1 - max(0, difference - 0.02) / 0.08)
        case .fractionOfLap: confidence = max(0, 1 - difference / 0.2)
        }
    }

    /// The delta at the end of the reference lap: the lap's time minus the reference's, when
    /// the two are the same length.
    public var total: Double { delta.last ?? 0 }

    /// Seconds behind (+) or ahead (−) `distance` metres into the reference lap.
    public func delta(atDistance distance: Double) -> Double { interpolate(delta, at: distance) }

    public func speedDelta(atDistance distance: Double) -> Double? {
        speedDelta.map { interpolate($0, at: distance) }
    }

    /// Seconds lost (+) or gained (−) between two distances into the reference lap: the change in
    /// the delta across that stretch, which is what "0.3 s lost in Turn 4" means.
    public func loss(from start: Double, to end: Double) -> Double {
        delta(atDistance: end) - delta(atDistance: start)
    }

    private func interpolate(_ values: [Double], at distance: Double) -> Double {
        guard values.count == distances.count, distances.count >= 2 else { return values.first ?? 0 }
        if distance <= 0 { return values[0] }
        guard let length = distances.last, distance < length else { return values[values.count - 1] }
        let step = distances[1] - distances[0]
        let lower = min(step > 0 ? Int(distance / step) : 0, distances.count - 2)
        let span = distances[lower + 1] - distances[lower]
        let fraction = span > 0 ? (distance - distances[lower]) / span : 0
        return values[lower] + (values[lower + 1] - values[lower]) * min(max(fraction, 0), 1)
    }
}
