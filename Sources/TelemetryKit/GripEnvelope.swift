import Foundation

/// How much combined G a car has shown it can reach, in each direction round the friction circle
/// (#558): braking, cornering either way, accelerating, and every mix of them. A car brakes harder
/// than it accelerates and may corner harder one way than the other, so the limit is a shape, not
/// a circle.
///
/// Each reach is a high percentile of the combined G measured in that direction rather than the
/// single highest, so one spike — a kerb, a bump in the logger's mount — does not set the limit.
public struct GripEnvelope: Hashable, Codable, Sendable {
    /// Sectors round the circle.
    public static let directions = 16

    /// The combined G reached in each direction, in g, sector 0 centred on straight braking and
    /// going round through cornering right, accelerating and cornering left.
    public var reach: [Double]

    public init(reach: [Double]) {
        self.reach = reach.count == Self.directions ? reach : Array(repeating: reach.max() ?? 1, count: Self.directions)
    }

    /// The same reach every way: a circle.
    public init(circle radius: Double) { reach = Array(repeating: radius, count: Self.directions) }

    /// The most the car reached any way.
    public var peak: Double { reach.max() ?? 0 }
    /// Straight braking, cornering (the better side) and accelerating, for a sentence.
    public var braking: Double { reach[0] }
    public var cornering: Double { max(reach[4], reach[12]) }
    public var accelerating: Double { reach[8] }

    /// The sector a direction falls in; `longitudinal` positive accelerating, `lateral` positive right.
    static func sector(lateral: Double, longitudinal: Double) -> Double {
        // 0 at straight braking (longitudinal negative), clockwise through right.
        var angle = atan2(lateral, -longitudinal)
        if angle < 0 { angle += 2 * .pi }
        return angle / (2 * .pi) * Double(directions)
    }

    /// The limit in the direction of a point, between the two sectors either side of it.
    public func limit(lateral: Double, longitudinal: Double) -> Double {
        let position = Self.sector(lateral: lateral, longitudinal: longitudinal)
        let lower = Int(position.rounded(.down)) % Self.directions
        let upper = (lower + 1) % Self.directions
        let fraction = position - position.rounded(.down)
        return reach[lower] * (1 - fraction) + reach[upper] * fraction
    }

    /// How much of the limit a point uses: 0 at rest, 1 at the limit, above 1 past it.
    public func used(lateral: Double, longitudinal: Double) -> Double {
        let combined = hypot(lateral, longitudinal)
        let limit = limit(lateral: lateral, longitudinal: longitudinal)
        return limit > 0 ? combined / limit : 0
    }

    /// Every reach times `factor`: the driver's own adjustment.
    public func scaled(by factor: Double) -> GripEnvelope { GripEnvelope(reach: reach.map { $0 * factor }) }

    /// The envelope of points `(lateral, longitudinal)` in g; `nil` with too few to say. A sector
    /// with too few points of its own takes its neighbours' reach.
    public static func measure(
        _ points: [(lateral: Double, longitudinal: Double)], percentile: Double = 0.98, minimumPerSector: Int = 8
    ) -> GripEnvelope? {
        var sectors = Array(repeating: [Double](), count: directions)
        for point in points where point.lateral.isFinite && point.longitudinal.isFinite {
            let combined = hypot(point.lateral, point.longitudinal)
            guard combined > 0.05 else { continue }
            let index = Int(sector(lateral: point.lateral, longitudinal: point.longitudinal).rounded()) % directions
            sectors[index].append(combined)
        }
        var reach: [Double?] = sectors.map { values in
            guard values.count >= minimumPerSector else { return nil }
            let sorted = values.sorted()
            return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * percentile))]
        }
        // Braking and cornering both ways are the least a lap shows; without them there is no shape.
        guard reach.compactMap({ $0 }).count >= directions / 4, reach[0] != nil, reach[4] != nil || reach[12] != nil
        else { return nil }
        for _ in 0..<directions where reach.contains(where: { $0 == nil }) {
            reach = reach.indices.map { index in
                reach[index]
                    ?? {
                        let neighbours = [
                            reach[(index + directions - 1) % directions], reach[(index + 1) % directions],
                        ]
                        .compactMap { $0 }
                        return neighbours.isEmpty ? nil : neighbours.reduce(0, +) / Double(neighbours.count)
                    }()
            }
        }
        return GripEnvelope(reach: reach.map { $0 ?? 0 })
    }

    /// Several sessions' envelopes as a range: the typical one (the median each way) and the best
    /// (the most each way). `nil` for none.
    public static func range(of envelopes: [GripEnvelope]) -> (typical: GripEnvelope, best: GripEnvelope)? {
        guard !envelopes.isEmpty else { return nil }
        let typical = (0..<directions).map { index -> Double in
            let values = envelopes.map { $0.reach[index] }.sorted()
            return values[values.count / 2]
        }
        let best = (0..<directions).map { index in envelopes.map { $0.reach[index] }.max() ?? 0 }
        return (GripEnvelope(reach: typical), GripEnvelope(reach: best))
    }
}

extension GripEnvelope {
    /// The envelope of `session`'s complete laps, from the G its profiles carry (recorded, else
    /// derived from the speed trace and the path), at speeds a car is being driven at.
    public static func measure(_ session: TelemetrySession, movingSpeed: Double = 8) -> GripEnvelope? {
        let laps = session.laps.filter { $0.isComplete && $0.end != nil && $0.kind == .lap }
        let points = laps.compactMap { LapProfile(lap: $0, in: session) }.flatMap { profile in
            profile.distances.indices.compactMap { index -> (lateral: Double, longitudinal: Double)? in
                guard let lateral = profile.channels[.lateralG]?[index],
                    let longitudinal = profile.channels[.longitudinalG]?[index],
                    (profile.channels[.speed]?[index] ?? movingSpeed) >= movingSpeed
                else { return nil }
                return (lateral, longitudinal)
            }
        }
        return measure(points)
    }
}

extension GripEnvelope {
    /// `gripUsed` (#558): at every sample the logger recorded both G, the share of the grip the car
    /// reached in that session it is using, 0–100 %. Against the session's own envelope, so a video
    /// renders the same whatever the logbook learns later; `nil` without recorded lateral and
    /// longitudinal G, or too little driving to know the envelope.
    public static func gripUsedChannel(of session: TelemetrySession, movingSpeed: Double = 8) -> Channel? {
        guard session[.gripUsed] == nil, let lateral = session[.lateralG], let longitudinal = session[.longitudinalG]
        else { return nil }
        let speed = session[.speed]
        struct Sample {
            let time: Double
            let lateral: Double
            let longitudinal: Double
        }
        let samples = zip(lateral.times, lateral.values).compactMap { time, lat -> Sample? in
            guard let long = longitudinal.value(at: time), lat.isFinite, long.isFinite else { return nil }
            return Sample(time: time, lateral: lat, longitudinal: long)
        }
        let moving = samples.filter { sample in
            (speed?.value(at: sample.time) ?? movingSpeed).map { $0 >= movingSpeed } ?? true
        }
        guard samples.count >= 4,
            let envelope = measure(moving.map { ($0.lateral, $0.longitudinal) })
        else { return nil }
        return Channel(
            role: .gripUsed, name: "Grip used", unit: .percent, times: samples.map(\.time),
            values: samples.map { min(150, envelope.used(lateral: $0.lateral, longitudinal: $0.longitudinal) * 100) })
    }
}
