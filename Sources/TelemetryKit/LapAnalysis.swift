import Foundation

/// Laps as data (#556): a reference lap and up to three more, from one session or several, laid
/// over each other by the place on the track, so delta-T, speed, any channel, the map and the
/// friction circle all name the same spot with one number: metres into the reference lap.
///
/// A lap a little longer or shorter than the reference — a wider line, another session's start —
/// is stretched to it, as Compare Laps retimes by the fraction of the lap: a point a third of the
/// way round one lap is a third of the way round the other.
public struct LapAnalysis: Sendable {
    /// The most laps laid over each other, the reference among them.
    public static let maximumLaps = 4

    /// One lap: its profile, what to call it, and whether it is the reference.
    public struct Trace: Sendable, Identifiable {
        public let id: Int
        public let label: String
        public let profile: LapProfile
        /// The lap's length over the reference's: how far into this lap a reference distance is.
        public let scale: Double

        public var isReference: Bool { id == 0 }
        public var lapTime: Double { profile.elapsed.last ?? 0 }

        /// Metres into this lap at `distance` metres into the reference.
        public func distance(atReference distance: Double) -> Double { distance * scale }
    }

    /// One point of a line to draw: metres into the reference lap and the value there.
    public struct Point: Sendable, Hashable {
        public let distance: Double
        public let value: Double

        public init(distance: Double, value: Double) {
            self.distance = distance
            self.value = value
        }
    }

    /// One point of the friction circle, in g.
    public struct GPoint: Sendable, Hashable {
        public let distance: Double
        public let lateral: Double
        public let longitudinal: Double
    }

    /// A corner of the reference lap, to zoom the traces to.
    public struct CornerSpan: Sendable, Hashable {
        /// The circuit's name for it, or its number: "3", "Carousel".
        public let label: String
        public let range: ClosedRange<Double>
        public let apex: Double

        /// "Turn 3", as Coaching says it.
        public var title: String { "Turn \(label)" }
    }

    /// The reference first.
    public let traces: [Trace]
    public let corners: [CornerSpan]

    public var reference: Trace { traces[0] }
    public var length: Double { reference.profile.distances.last ?? 0 }

    /// `profiles[0]` is the reference; any past `maximumLaps` are left out. `nil` without a profile.
    public init?(
        profiles: [(label: String, profile: LapProfile)], corners: [CornerSpan] = []
    ) {
        let kept = Array(profiles.prefix(Self.maximumLaps))
        guard let first = kept.first, let referenceLength = first.profile.distances.last, referenceLength > 0
        else { return nil }
        traces = kept.enumerated().map { index, item in
            let length = item.profile.distances.last ?? referenceLength
            return Trace(id: index, label: item.label, profile: item.profile, scale: length / referenceLength)
        }
        self.corners = corners
    }

    // MARK: - Lines

    /// Grid distances of the reference no more than `points` apart in count, across `range`.
    public func grid(in range: ClosedRange<Double>? = nil, points: Int = 600) -> [Double] {
        let span = range ?? 0...length
        let lower = max(0, span.lowerBound)
        let upper = min(length, span.upperBound)
        guard upper > lower, points > 1 else { return [] }
        let step = max(reference.profile.stepMeters, (upper - lower) / Double(points - 1))
        return Array(stride(from: lower, through: upper, by: step))
    }

    /// Seconds this lap is behind the reference at each place: positive slower, negative ahead.
    /// The reference's own line is zero all the way.
    public func delta(_ trace: Trace, at distances: [Double]) -> [Point] {
        distances.map { distance in
            let own = trace.profile.elapsed(atDistance: trace.distance(atReference: distance))
            return Point(distance: distance, value: own - reference.profile.elapsed(atDistance: distance))
        }
    }

    /// `role`'s value on the lap at each place; places the lap does not have it are left out.
    public func values(of role: ChannelRole, _ trace: Trace, at distances: [Double]) -> [Point] {
        distances.compactMap { distance in
            trace.profile.value(of: role, atDistance: trace.distance(atReference: distance)).map {
                Point(distance: distance, value: $0)
            }
        }
    }

    /// The lap's lateral and longitudinal G at each place, where it has both.
    public func frictionCircle(_ trace: Trace, at distances: [Double]) -> [GPoint] {
        distances.compactMap { distance in
            let own = trace.distance(atReference: distance)
            guard let lateral = trace.profile.value(of: .lateralG, atDistance: own),
                let longitudinal = trace.profile.value(of: .longitudinalG, atDistance: own)
            else { return nil }
            return GPoint(distance: distance, lateral: lateral, longitudinal: longitudinal)
        }
    }

    /// Where the lap is on the ground at a place.
    public func position(_ trace: Trace, at distance: Double) -> (latitude: Double, longitude: Double)? {
        trace.profile.position(atDistance: trace.distance(atReference: distance))
    }

    /// The reference's path, `points` positions round the lap.
    /// A place on the reference's path.
    public struct PathPoint: Sendable, Hashable {
        public let distance: Double
        public let latitude: Double
        public let longitude: Double
    }

    public func path(points: Int = 400) -> [PathPoint] {
        grid(points: points).compactMap { distance in
            position(reference, at: distance).map {
                PathPoint(distance: distance, latitude: $0.latitude, longitude: $0.longitude)
            }
        }
    }

    /// The place on the reference's path nearest a position: what a click on the map means.
    public func distance(nearestLatitude latitude: Double, longitude: Double) -> Double? {
        let scale = cos(latitude * .pi / 180)
        return path(points: 800).min { a, b in
            hypot(a.latitude - latitude, (a.longitude - longitude) * scale)
                < hypot(b.latitude - latitude, (b.longitude - longitude) * scale)
        }?.distance
    }

    /// The corner a place is in, or the nearest one within `margin` metres of it.
    public func corner(at distance: Double, margin: Double = 60) -> CornerSpan? {
        corners.min { a, b in Self.gap(distance, a.range) < Self.gap(distance, b.range) }
            .flatMap { Self.gap(distance, $0.range) <= margin ? $0 : nil }
    }

    /// The span to show for a corner: from a little before it begins to a little after it ends,
    /// so the braking into it and the drive out are on screen.
    public func zoom(to corner: CornerSpan, lead: Double = 150, follow: Double = 80) -> ClosedRange<Double> {
        max(0, corner.range.lowerBound - lead)...min(length, corner.range.upperBound + follow)
    }

    static func gap(_ distance: Double, _ range: ClosedRange<Double>) -> Double {
        range.contains(distance) ? 0 : min(abs(distance - range.lowerBound), abs(distance - range.upperBound))
    }

    // MARK: - At the cursor

    /// What each lap reads at one place, for the cursor's readout.
    public struct Reading: Sendable, Identifiable {
        public var id: Int { trace }
        public let trace: Int
        public let elapsed: Double
        public let delta: Double
        public let values: [ChannelRole: Double]
    }

    public func readings(at distance: Double, roles: [ChannelRole]) -> [Reading] {
        let referenceElapsed = reference.profile.elapsed(atDistance: distance)
        return traces.map { trace in
            let own = trace.distance(atReference: distance)
            let elapsed = trace.profile.elapsed(atDistance: own)
            var values: [ChannelRole: Double] = [:]
            for role in roles { values[role] = trace.profile.value(of: role, atDistance: own) }
            return Reading(trace: trace.id, elapsed: elapsed, delta: elapsed - referenceElapsed, values: values)
        }
    }

    /// Session time on the lap at a place: where its video is.
    public func sessionTime(_ trace: Trace, at distance: Double) -> Double {
        trace.profile.time(atDistance: trace.distance(atReference: distance))
    }
}

extension LapAnalysis {
    /// The roles a profile should carry so every panel can draw: the usual ones, and any the
    /// driver has asked for.
    public static func roles(adding extra: [ChannelRole]) -> [ChannelRole] {
        LapProfile.defaultRoles + extra.filter { !LapProfile.defaultRoles.contains($0) }
    }

    /// `session`'s corners on `lap`, named as Coaching names them, as spans to zoom to.
    public static func corners(of lap: Lap, in session: TelemetrySession) -> [CornerSpan] {
        let corners = session.agreedCorners(of: lap)
        let names = session.cornerNames(for: corners)
        return corners.enumerated().map { index, corner in
            CornerSpan(
                label: index < names.count ? names[index].label : String(index + 1),
                range: corner.startDistance...max(corner.startDistance, corner.endDistance), apex: corner.apexDistance)
        }
    }
}
