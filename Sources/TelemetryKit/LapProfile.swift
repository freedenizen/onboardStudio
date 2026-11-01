import Foundation

/// A stretch of driving, usually one lap, as functions of distance travelled since it began.
///
/// Coaching compares two laps *at the same place on the track*, and the place is named by distance
/// into the lap, as sectors and the delta channels already do. A profile resamples the session's
/// channels onto a uniform distance grid, so a brake point measured on a 10 Hz GoPro log and one
/// measured on a 100 Hz RaceChrono log are comparable — the same reason `CornerDetector` resamples
/// before it measures curvature.
///
/// Channels the logger did not record are derived where the physics allows: speed from the
/// distance channel, longitudinal G from the speed trace, lateral G from speed and the bend of the
/// path. `source(of:)` says which, so anything shown to the driver can say "from the speed trace".
/// The derived values live only in the profile and are never added to the session, so no saved
/// project renders differently for their existence.
public struct LapProfile: Sendable {
    /// A span of session time.
    public struct Window: Sendable, Hashable, Codable {
        public var start: Double
        public var end: Double

        public init(start: Double, end: Double) {
            self.start = start
            self.end = end
        }

        public var duration: Double { end - start }
    }

    /// Where a profile's channel came from.
    public enum Source: String, Sendable, Codable {
        /// The logger recorded it.
        case recorded
        /// Worked out from how distance grew with time (speed) or how speed changed (longitudinal G).
        case speedTrace
        /// Worked out from the bend of the GPS path (heading, lateral G).
        case position
    }

    /// The channels a profile carries when the session has them, besides position and heading.
    public static let defaultRoles: [ChannelRole] = [
        .speed, .throttle, .brake, .brakePressureFront, .brakePressureRear, .longitudinalG, .lateralG,
        .steeringAngle, .rpm, .gear,
    ]

    /// Standard gravity, which turns a derived acceleration into the g the recorded channels use.
    static let gravity = 9.80665

    public let window: Window
    /// What to call it to the driver: "Lap 5", "Fastest rolling lap", "Optimal lap".
    public let label: String
    public let stepMeters: Double
    /// Distance into the window at each grid point: `0, step, 2·step, …`, ending on `lengthMeters`.
    public let distances: [Double]
    /// Seconds since the window began at each grid point; never decreasing.
    public let elapsed: [Double]
    public let latitude: [Double]?
    public let longitude: [Double]?
    /// Direction of travel at each grid point in degrees (0 = north, clockwise), from the path.
    public let heading: [Double]?
    /// Values at each grid point, in the role's canonical unit where one exists (speed in m/s,
    /// G in g); otherwise as recorded.
    public let channels: [ChannelRole: [Double]]
    public let sources: [ChannelRole: Source]
    /// The laps this profile was cut from, in grid order. One entry for a plain lap; several for
    /// a rolling lap re-based to the line or an optimal lap spliced from the best sectors.
    public let pieces: [Piece]

    /// A stretch of one lap that makes up part of a profile.
    public struct Piece: Sendable, Hashable, Codable {
        public let lapNumber: Int
        /// Distances into the profile this piece covers.
        public let range: ClosedRange<Double>
        /// Distance into the source lap at which the piece begins, so a profile distance can be
        /// taken back to the lap it came from: `sourceFrom + (distance − range.lowerBound)`.
        public let sourceFrom: Double

        public init(lapNumber: Int, range: ClosedRange<Double>, sourceFrom: Double = 0) {
            self.lapNumber = lapNumber
            self.range = range
            self.sourceFrom = sourceFrom
        }

        /// Distance into the source lap of a distance into the profile within this piece.
        public func sourceDistance(at distance: Double) -> Double { sourceFrom + (distance - range.lowerBound) }
    }

    /// The piece a distance into the profile falls in.
    public func piece(at distance: Double) -> Piece? {
        pieces.last { $0.range.lowerBound <= distance } ?? pieces.first
    }

    public var lengthMeters: Double { distances.last ?? 0 }
    /// Seconds the profile took, start to finish.
    public var duration: Double { elapsed.last ?? 0 }
    /// Distances into the profile where one piece hands over to the next; empty for a plain lap.
    public var seams: [Double] { pieces.dropFirst().map(\.range.lowerBound) }
    /// Whether this is one real stretch of driving (a lap, a rolling lap) or several joined.
    public var isSpliced: Bool { pieces.count > 1 }
    public var hasPosition: Bool { latitude != nil && longitude != nil }
    public var count: Int { distances.count }

    /// `lap` as a profile, labelled "Lap N". `nil` for an incomplete lap or one too short to grid.
    public init?(lap: Lap, in session: TelemetrySession, stepMeters: Double = 2) {
        guard let end = lap.end else { return nil }
        self.init(
            window: Window(start: lap.start, end: end), in: session, label: "Lap \(lap.number)", stepMeters: stepMeters,
            lapNumber: lap.number)
    }

    /// `window` of `session` on a grid every `stepMeters`. `nil` without a distance channel, for a
    /// window that does not move at least a few steps, or for one outside the recording.
    ///
    /// `smoothingMeters` is the moving-average window for the derived channels only; a recorded
    /// channel is sampled as it is. `lapNumber` names the piece; 0 when the window is not a lap.
    public init?(
        window: Window, in session: TelemetrySession, label: String, stepMeters: Double = 2,
        roles: [ChannelRole] = LapProfile.defaultRoles, smoothingMeters: Double = 25, lapNumber: Int = 0
    ) {
        let step = max(0.5, stepMeters)
        guard let distance = session[.distance], let grid = Self.grid(window: window, distance: distance, step: step)
        else { return nil }
        self.init(
            window: window, label: label, stepMeters: step, distances: grid.distances, times: grid.times,
            elapsed: grid.times.map { $0 - window.start },
            pieces: [Piece(lapNumber: lapNumber, range: 0...(grid.distances.last ?? 0))], session: session,
            roles: roles, smoothingMeters: smoothingMeters)
    }

    /// Samples `session` at `times`, one per grid point, and derives what is missing. The grid,
    /// the elapsed times and the pieces are the caller's: a window supplies one piece, a splice
    /// several.
    init(
        window: Window, label: String, stepMeters: Double, distances: [Double], times: [Double], elapsed: [Double],
        pieces: [Piece], session: TelemetrySession, roles: [ChannelRole], smoothingMeters: Double
    ) {
        self.window = window
        self.label = label
        self.stepMeters = stepMeters
        self.distances = distances
        self.elapsed = elapsed
        self.pieces = pieces

        var channels: [ChannelRole: [Double]] = [:]
        var sources: [ChannelRole: Source] = [:]
        for role in roles {
            guard let channel = session[role], !channel.isEmpty else { continue }
            channels[role] = Self.sample(channel, at: times, as: role)
            sources[role] = .recorded
        }

        if let latChannel = session[.latitude], let lonChannel = session[.longitude] {
            let lat = times.map { latChannel.value(at: $0) ?? 0 }
            let lon = times.map { lonChannel.value(at: $0) ?? 0 }
            latitude = lat
            longitude = lon
            heading = Self.headings(latitude: lat, longitude: lon)
        } else {
            latitude = nil
            longitude = nil
            heading = session[.heading].map { channel in times.map { channel.value(at: $0) ?? 0 } }
        }

        let derived = Self.derived(
            from: channels, distances: distances, elapsed: elapsed, heading: heading,
            smoothingPoints: max(1, Int((smoothingMeters / stepMeters).rounded())))
        self.channels = channels.merging(derived.channels) { recorded, _ in recorded }
        self.sources = sources.merging(derived.sources) { recorded, _ in recorded }
    }

    /// The grid points of `window` and the session time at each; `nil` when the window does not
    /// move at least four steps.
    static func grid(window: Window, distance: Channel, step: Double) -> (distances: [Double], times: [Double])? {
        guard window.end > window.start, let startDistance = distance.value(at: window.start),
            let endDistance = distance.value(at: window.end), endDistance - startDistance >= step * 4
        else { return nil }
        let length = endDistance - startDistance
        var distances: [Double] = []
        var times: [Double] = []
        var travelled = 0.0
        while travelled < length - 1e-6 {
            guard
                let time = LapComparison.time(
                    atDistance: startDistance + travelled, in: distance, between: window.start, and: window.end)
            else { break }
            distances.append(travelled)
            times.append(min(max(time, window.start), window.end))
            travelled += step
        }
        guard distances.count >= 4 else { return nil }
        distances.append(length)
        times.append(window.end)
        times[0] = window.start
        // The distance channel can hold or jitter while the car is stopped; time must not go back.
        for index in 1..<times.count where times[index] < times[index - 1] { times[index] = times[index - 1] }
        return (distances, times)
    }

    /// `channel` at each of `times`, in `role`'s canonical unit where one exists.
    static func sample(_ channel: Channel, at times: [Double], as role: ChannelRole) -> [Double] {
        let canonical = TelemetryUnit.canonical(for: role)
        return times.map { time in
            let value = channel.value(at: time) ?? 0
            guard let canonical, canonical != channel.unit else { return value }
            return channel.unit.convert(value, to: canonical) ?? value
        }
    }

    /// Speed, longitudinal G and lateral G for whichever of them the logger did not record.
    static func derived(
        from recorded: [ChannelRole: [Double]], distances: [Double], elapsed: [Double], heading: [Double]?,
        smoothingPoints: Int
    ) -> (channels: [ChannelRole: [Double]], sources: [ChannelRole: Source]) {
        var channels: [ChannelRole: [Double]] = [:]
        var sources: [ChannelRole: Source] = [:]
        let speed: [Double]
        if let recordedSpeed = recorded[.speed] {
            speed = recordedSpeed
        } else {
            // Not smoothed: the step either side of a grid point already averages over two steps,
            // and smoothing a speed trace lifts every minimum, which is the one number a corner
            // reading must not move.
            speed = speeds(distances: distances, elapsed: elapsed)
            channels[.speed] = speed
            sources[.speed] = .speedTrace
        }
        if recorded[.longitudinalG] == nil {
            channels[.longitudinalG] = smoothed(
                longitudinalG(speed: speed, distances: distances), points: smoothingPoints)
            sources[.longitudinalG] = .speedTrace
        }
        if recorded[.lateralG] == nil, let heading {
            channels[.lateralG] = smoothed(
                lateralG(speed: speed, heading: heading, distances: distances), points: smoothingPoints)
            sources[.lateralG] = .position
        }
        return (channels, sources)
    }

    // MARK: - Reading

    public func has(_ role: ChannelRole) -> Bool { channels[role] != nil }

    public func source(of role: ChannelRole) -> Source? { sources[role] }

    /// Seconds the window needed to get `distance` metres in (clamped to the window).
    public func elapsed(atDistance distance: Double) -> Double { interpolate(elapsed, at: distance) }

    /// Session time at which the window was `distance` metres in.
    public func time(atDistance distance: Double) -> Double { window.start + elapsed(atDistance: distance) }

    /// `role`'s value `distance` metres in, or `nil` when the profile does not carry it.
    public func value(of role: ChannelRole, atDistance distance: Double) -> Double? {
        channels[role].map { interpolate($0, at: distance) }
    }

    public func position(atDistance distance: Double) -> (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (interpolate(latitude, at: distance), interpolate(longitude, at: distance))
    }

    /// Direction of travel `distance` metres in, degrees clockwise from north.
    public func heading(atDistance distance: Double) -> Double? {
        guard let heading, count >= 2 else { return nil }
        let segment = segment(at: distance)
        var turn = heading[segment.upper] - heading[segment.lower]
        if turn > 180 { turn -= 360 }
        if turn < -180 { turn += 360 }
        return (heading[segment.lower] + turn * segment.fraction + 360).truncatingRemainder(dividingBy: 360)
    }

    /// How far in the window was `seconds` after it began (clamped to the window).
    public func distance(atElapsed seconds: Double) -> Double {
        guard let first = elapsed.first, let last = elapsed.last else { return 0 }
        if seconds <= first { return 0 }
        if seconds >= last { return lengthMeters }
        let upper = elapsed.firstIndex(atOrAfter: seconds)
        let lower = max(0, upper - 1)
        let span = elapsed[upper] - elapsed[lower]
        let fraction = span > 0 ? (seconds - elapsed[lower]) / span : 0
        return distances[lower] + (distances[upper] - distances[lower]) * fraction
    }

    /// The grid points a distance falls between, and how far across.
    struct Segment {
        let lower: Int
        let upper: Int
        let fraction: Double
    }

    func segment(at distance: Double) -> Segment {
        guard count >= 2 else { return Segment(lower: 0, upper: 0, fraction: 0) }
        if distance <= 0 { return Segment(lower: 0, upper: 1, fraction: 0) }
        if distance >= lengthMeters { return Segment(lower: count - 2, upper: count - 1, fraction: 1) }
        let lower = min(Int(distance / stepMeters), count - 2)
        let span = distances[lower + 1] - distances[lower]
        let fraction = span > 0 ? (distance - distances[lower]) / span : 0
        return Segment(lower: lower, upper: lower + 1, fraction: min(max(fraction, 0), 1))
    }

    private func interpolate(_ values: [Double], at distance: Double) -> Double {
        guard values.count == count, count >= 2 else { return values.first ?? 0 }
        let segment = segment(at: distance)
        return values[segment.lower] + (values[segment.upper] - values[segment.lower]) * segment.fraction
    }
}
