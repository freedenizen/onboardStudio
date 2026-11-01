import Foundation

@testable import TelemetryKit

/// Laps of the synthetic stadium circuit driven the way a driver drives: flat out on the
/// straights, braking at a constant deceleration to a minimum speed near each apex, then
/// accelerating away. Every brake point, minimum and pick-up follows from the numbers given, so
/// a test can say what a metric must read rather than what it happened to read once.
enum CoachingFixture {
    /// How one lap takes both bends.
    struct Driving {
        /// Top speed on the straights, m/s.
        var topSpeed: Double = 40
        /// The slowest the car gets, m/s.
        var minimumSpeed: Double = 15
        /// Where the slowest point is, metres after the apex (negative = before).
        var minimumOffset: Double = 0
        /// Braking deceleration, m/s².
        var deceleration: Double = 4
        /// Acceleration out, m/s².
        var acceleration: Double = 2

        /// Metres before the slowest point at which braking must begin.
        var brakingDistance: Double { (topSpeed * topSpeed - minimumSpeed * minimumSpeed) / (2 * deceleration) }
        /// Metres before the apex at which braking begins.
        var brakePointBeforeApex: Double { brakingDistance - minimumOffset }
    }

    static let fast = Driving()
    /// Brakes earlier and softer, over-slows, and finds its minimum after the apex.
    static let slow = Driving(minimumSpeed: 13, minimumOffset: 20, deceleration: 3)

    static func geometry() -> SyntheticTrack.Geometry { SyntheticTrack.geometry() }

    /// Speed at `into` metres into a lap driven as `driving`.
    static func speed(at into: Double, driving d: Driving, geometry g: SyntheticTrack.Geometry) -> Double {
        let apexes = [g.firstBend, g.secondBend].map { ($0.lowerBound + $0.upperBound) / 2 }
        var speed = d.topSpeed
        for lapOffset in [-g.lapLength, 0, g.lapLength] {
            for apex in apexes {
                let slowest = apex + d.minimumOffset + lapOffset
                let curve =
                    into < slowest
                    ? (d.minimumSpeed * d.minimumSpeed + 2 * d.deceleration * (slowest - into)).squareRoot()
                    : (d.minimumSpeed * d.minimumSpeed + 2 * d.acceleration * (into - slowest)).squareRoot()
                speed = min(speed, curve)
            }
        }
        return speed
    }

    /// A session of `drivings.count` laps, one per entry. With `pedals`, a brake channel (0/1)
    /// and a throttle channel (0–100) are recorded from the same speed curve: brake while
    /// slowing, throttle while accelerating.
    static func session(drivings: [Driving], pedals: Bool = false) -> TelemetrySession {
        let g = geometry()
        var session = SyntheticTrack.session(speed: fast.topSpeed, laps: drivings.count) { lap, into in
            speed(at: into, driving: drivings[lap], geometry: g) / fast.topSpeed
        }
        guard pedals, let distance = session[.distance] else { return session }
        var brake: [Double] = []
        var throttle: [Double] = []
        for (index, time) in distance.times.enumerated() {
            let lap = min(Int(distance.values[index] / g.lapLength), drivings.count - 1)
            let into = distance.values[index] - Double(lap) * g.lapLength
            let now = speed(at: into, driving: drivings[lap], geometry: g)
            let next = speed(at: into + 1, driving: drivings[lap], geometry: g)
            brake.append(next < now - 1e-9 ? 1 : 0)
            throttle.append(next > now + 1e-9 ? 100 : (next < now - 1e-9 ? 0 : 100))
            _ = time
        }
        session.add(
            Channel(
                role: .brake, name: "brake", unit: .none, times: distance.times, values: brake, interpolation: .step))
        session.add(
            Channel(
                role: .throttle, name: "throttle", unit: .percent, times: distance.times, values: throttle,
                interpolation: .step))
        return session
    }
}
