import CoreGraphics
import Foundation
import ProjectModel

/// Placing and rotating a start/finish line by pointing at the drawn track map.
///
/// Typing six decimal places of latitude is the wrong gesture for a line on a circuit, so the
/// editor draws the line over the map object and lets it be dragged. All of the arithmetic lives
/// here rather than in the view so it can be tested without a window: the view is left with
/// nothing but mouse events.
///
/// Distances use the same metres-per-degree constants as `LapDetector`, so the line the driver
/// sees is exactly as wide as the line that detects the crossing.
public enum TrackMapEditing {
    static let metresPerDegreeLatitude = 110_540.0
    static let metresPerDegreeLongitude = 111_320.0

    /// The drawn line: its centre, its two true ends, and the two points that rotate it.
    ///
    /// The ends and the handles are usually the same place. They part company on a wide map, where
    /// a 25 m line across a 4 km circuit is a few points long and its two ends land almost on top
    /// of each other — grabbable by nobody. The line keeps its true length, because that length is
    /// the corridor a crossing has to fall inside, and the handles move out to arm's length.
    public struct Line: Equatable, Sendable {
        public let centre: CGPoint
        public let right: CGPoint
        public let left: CGPoint
        public let rightHandle: CGPoint
        public let leftHandle: CGPoint
        /// Where the car is heading when it crosses, in compass degrees — the drawn arrow.
        public let headingDegrees: Double
    }

    /// Which part of the line a click landed on.
    public enum Handle: Equatable, Sendable {
        case body
        case rightEnd
        case leftEnd
    }

    /// The line `spec` describes, drawn across the track inside `bounds`.
    ///
    /// A line with no heading is crossed in whatever direction the track runs there, which is what
    /// `LapDetector` does, so it is drawn square to the trace beneath it rather than square to an
    /// arbitrary north.
    /// `minimumHandleDistance` is in the units of `bounds`: how far from the centre the rotation
    /// handles sit at the very least, so they stay apart enough to be told from each other.
    public static func line(
        _ spec: LapLineSpec, projection: TrackProjection, in bounds: CGRect, minimumHandleDistance: Double = 0
    ) -> Line {
        let centre = projection.point(latitude: spec.latitude, longitude: spec.longitude, in: bounds)
        let heading =
            spec.headingDegrees
            ?? projection.traceHeading(nearest: centre, in: bounds)
            ?? 0
        let half = max(spec.halfWidthMeters, 1)
        func end(_ bearing: Double) -> CGPoint {
            let there = coordinate(
                from: (spec.latitude, spec.longitude), bearing: bearing, metres: half,
                cosLat: projection.basis.cosLat)
            return projection.point(latitude: there.latitude, longitude: there.longitude, in: bounds)
        }
        let right = end(heading + 90)
        let left = end(heading - 90)
        return Line(
            centre: centre, right: right, left: left,
            rightHandle: reachable(right, from: centre, atLeast: minimumHandleDistance),
            leftHandle: reachable(left, from: centre, atLeast: minimumHandleDistance),
            headingDegrees: heading)
    }

    /// `end` pushed out along its own direction until it is at least `distance` from `centre`.
    static func reachable(_ end: CGPoint, from centre: CGPoint, atLeast distance: Double) -> CGPoint {
        let length = hypot(end.x - centre.x, end.y - centre.y)
        guard length > 0, length < distance else { return end }
        let scale = distance / length
        return CGPoint(x: centre.x + (end.x - centre.x) * scale, y: centre.y + (end.y - centre.y) * scale)
    }

    /// What a click at `point` grabs, or `nil` for a click that missed the line entirely.
    ///
    /// The ends win over the body, because they are inside it: a line only a few tolerances long
    /// would otherwise be impossible to rotate.
    public static func handle(at point: CGPoint, of line: Line, tolerance: Double) -> Handle? {
        if hypot(point.x - line.rightHandle.x, point.y - line.rightHandle.y) <= tolerance { return .rightEnd }
        if hypot(point.x - line.leftHandle.x, point.y - line.leftHandle.y) <= tolerance { return .leftEnd }
        return distance(from: point, toSegmentFrom: line.left, to: line.right) <= tolerance ? .body : nil
    }

    /// The line after a drag, or `nil` when the drag changed nothing worth recording.
    ///
    /// Dragging the body moves the line; dragging either end swings it about its centre, so the
    /// two gestures never fight over the same number.
    public static func dragged(
        _ spec: LapLineSpec, handle: Handle, to point: CGPoint, projection: TrackProjection, in bounds: CGRect
    ) -> LapLineSpec {
        var moved = spec
        switch handle {
        case .body:
            let there = projection.coordinate(at: point, in: bounds)
            moved.latitude = there.latitude
            moved.longitude = there.longitude
        case .rightEnd, .leftEnd:
            let there = projection.coordinate(at: point, in: bounds)
            let across = bearing(
                from: (spec.latitude, spec.longitude), to: there, cosLat: projection.basis.cosLat)
            // The right-hand end sits 90° clockwise of the direction of travel, so pointing it
            // somewhere new says where the travel direction now is.
            moved.headingDegrees = normalized(handle == .rightEnd ? across - 90 : across + 90)
        }
        return moved
    }

    /// A compass bearing folded into 0..<360, so a rotated line never reports −170°.
    public static func normalized(_ degrees: Double) -> Double {
        let wrapped = degrees.truncatingRemainder(dividingBy: 360)
        return wrapped < 0 ? wrapped + 360 : wrapped
    }

    /// The bearing from one coordinate to another, in compass degrees (0 = north, clockwise).
    static func bearing(
        from origin: (latitude: Double, longitude: Double), to destination: (latitude: Double, longitude: Double),
        cosLat: Double
    ) -> Double {
        let east = (destination.longitude - origin.longitude) * cosLat * metresPerDegreeLongitude
        let north = (destination.latitude - origin.latitude) * metresPerDegreeLatitude
        return normalized(atan2(east, north) * 180 / .pi)
    }

    /// The coordinate `metres` away from `origin` on a compass `bearing`.
    static func coordinate(
        from origin: (latitude: Double, longitude: Double), bearing: Double, metres: Double, cosLat: Double
    ) -> (latitude: Double, longitude: Double) {
        let radians = bearing * .pi / 180
        return (
            origin.latitude + metres * cos(radians) / metresPerDegreeLatitude,
            origin.longitude + metres * sin(radians) / (max(cosLat, 1e-9) * metresPerDegreeLongitude)
        )
    }

    /// Distance from a point to a line segment — how a click finds the body of the line.
    static func distance(from point: CGPoint, toSegmentFrom start: CGPoint, to end: CGPoint) -> Double {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return hypot(point.x - start.x, point.y - start.y) }
        let t = min(1, max(0, ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared))
        return hypot(point.x - (start.x + t * dx), point.y - (start.y + t * dy))
    }
}
