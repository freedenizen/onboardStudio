import Foundation

/// One lap as a car on the road (#413): its line in the track's metres, lifted onto the road's
/// elevation, and where it is at any moment since it started.
public struct ReplayLap: Identifiable, Sendable {
    public let id: UUID
    /// "Lap 4 · 1:56.88".
    public var label: String
    /// "Sonoma, 23 Aug 2026 · Miata" — which session it came from; empty for the home session.
    public var subtitle: String
    public let profile: LapProfile
    /// East, north and up at each grid point of the profile; up is the road's at that place plus
    /// a few centimetres, so the line sits on the tarmac whatever the lap's own altitude says.
    public let points: [SIMD3<Double>]
    public let lapTime: Double

    /// `nil` when the profile has no position.
    public init?(profile: LapProfile, on track: TrackModel, id: UUID = UUID(), label: String, subtitle: String = "") {
        guard let latitudes = profile.latitude, let longitudes = profile.longitude, profile.count >= 2 else {
            return nil
        }
        self.id = id
        self.label = label
        self.subtitle = subtitle
        self.profile = profile
        points = zip(latitudes, longitudes).map { latitude, longitude in
            let point = track.plane.point(latitude: latitude, longitude: longitude)
            return SIMD3(point.x, point.y, track.elevation(at: point) + 0.05)
        }
        lapTime = profile.elapsed.last ?? 0
    }

    /// Where a car is: on its line, pointing the way it was going, so far into its lap.
    public struct Placement: Sendable, Hashable {
        public var point: SIMD3<Double>
        /// Degrees clockwise from north.
        public var heading: Double
        public var distance: Double
    }

    /// Where the car is `seconds` after it started. Past its lap time it waits at the line.
    public func position(atElapsed seconds: Double) -> Placement {
        let distance = profile.distance(atElapsed: min(max(seconds, 0), lapTime))
        return Placement(
            point: point(atDistance: distance), heading: profile.heading(atDistance: distance) ?? 0, distance: distance)
    }

    /// The line `distance` metres into the lap.
    public func point(atDistance distance: Double) -> SIMD3<Double> {
        let segment = profile.segment(at: distance)
        guard segment.upper < points.count else { return points[min(segment.lower, points.count - 1)] }
        return points[segment.lower] + (points[segment.upper] - points[segment.lower]) * segment.fraction
    }

    public func elapsed(atDistance distance: Double) -> Double { profile.elapsed(atDistance: distance) }
}

/// Laps started together on one road (#413), as a replay shows them: who leads at any moment, and
/// how far behind each of the others is.
public struct ReplayField: Sendable {
    public struct Standing: Sendable, Identifiable {
        public var id: UUID { lap.id }
        public let lap: ReplayLap
        /// Metres into its lap.
        public let distance: Double
        /// Seconds behind the leader: how long ago the leader was where this car is now. 0 for
        /// the leader; once both have finished, the difference of their lap times.
        public let gapSeconds: Double
        public let finished: Bool
    }

    public let track: TrackModel
    public let laps: [ReplayLap]

    public init(track: TrackModel, laps: [ReplayLap]) {
        self.track = track
        self.laps = laps
    }

    /// The replay runs until the slowest lap is home.
    public var duration: Double { laps.map(\.lapTime).max() ?? 0 }

    private struct Place {
        let lap: ReplayLap
        let distance: Double
        let finished: Bool
    }

    /// Everyone's place `seconds` in, leader first.
    public func standings(at seconds: Double) -> [Standing] {
        let places = laps.map { lap -> Place in
            let finished = seconds >= lap.lapTime
            return Place(
                lap: lap, distance: finished ? lap.profile.lengthMeters : lap.position(atElapsed: seconds).distance,
                finished: finished)
        }
        // By distance; among those home, the quicker lap leads.
        let ordered = places.sorted { a, b in
            if a.finished != b.finished { return a.finished }
            if a.finished { return a.lap.lapTime < b.lap.lapTime }
            return a.distance > b.distance
        }
        guard let leader = ordered.first else { return [] }
        return ordered.map { place in
            let gap: Double
            if place.lap.id == leader.lap.id {
                gap = 0
            } else if place.finished, leader.finished {
                gap = place.lap.lapTime - leader.lap.lapTime
            } else {
                gap = max(0, seconds - leader.lap.elapsed(atDistance: place.distance))
            }
            return Standing(lap: place.lap, distance: place.distance, gapSeconds: gap, finished: place.finished)
        }
    }

    /// The replay time at which the leader of the lap being followed reaches `corner`'s apex,
    /// less `leadSeconds`, so a jump to a turn shows the braking too.
    public func time(toCorner index: Int, following lapID: UUID? = nil, leadSeconds: Double = 3) -> Double? {
        guard track.corners.indices.contains(index) else { return nil }
        let apex = track.corners[index].apexDistance
        let lap = laps.first { $0.id == lapID } ?? laps.min { $0.lapTime < $1.lapTime }
        guard let lap else { return nil }
        return max(0, lap.elapsed(atDistance: apex) - leadSeconds)
    }
}
