import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Local equirectangular projection of the session's positions, rotated, with bounds for fitting.
///
/// Public because the editor places a start/finish line by pointing at the drawn map, and the only
/// way a click can mean the same place the renderer drew is to go back through the very same
/// projection. A second copy of this arithmetic in the app would drift the first time either side
/// changed its padding.
public struct TrackProjection: Sendable {
    public struct Basis: Sendable {
        public let latitude0: Double
        public let longitude0: Double
        public let cosLat: Double
        public let rotation: Double

        public func project(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
            let x = (longitude - longitude0) * cosLat
            let y = latitude - latitude0
            return (x * cos(rotation) - y * sin(rotation), x * sin(rotation) + y * cos(rotation))
        }

        /// The inverse of `project`: undoes the rotation, then the longitude squeeze.
        public func unproject(x: Double, y: Double) -> (latitude: Double, longitude: Double) {
            let unrotatedX = x * cos(rotation) + y * sin(rotation)
            let unrotatedY = -x * sin(rotation) + y * cos(rotation)
            return (unrotatedY + latitude0, unrotatedX / max(cosLat, 1e-9) + longitude0)
        }
    }

    public let basis: Basis
    let points: [(x: Double, y: Double)]
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    /// The sample times the projection was built from, so anything drawn per point can line up
    /// with it without re-deriving which samples were used.
    let times: [Double]

    /// Unbroken stretches of `points`, as ranges into it.
    ///
    /// More than one only when samples were left out of the middle — the pit lane, the paddock —
    /// and then the outline must lift the pen rather than rule a line across the circuit from
    /// where the car left it to where it came back.
    let segments: [Range<Int>]

    /// `range` restricts the outline to part of the session — one lap, say — and `onTrack`, given
    /// per sample of the latitude channel, restricts it to where the car drove the circuit. The
    /// framing follows both: a map fits what it draws, not the paddock the car was parked in.
    public init?(
        session: TelemetrySession, rotationDegrees: Double, range: ClosedRange<Double>? = nil,
        onTrack: [Bool]? = nil
    ) {
        guard let lat = session[.latitude], let lon = session[.longitude], lat.count > 1 else { return nil }
        let wanted = onTrack?.count == lat.count ? onTrack : nil
        let indices: [Int] = lat.times.indices.filter {
            if let range, !range.contains(lat.times[$0]) { return false }
            if let wanted, !wanted[$0] { return false }
            return true
        }
        guard indices.count > 1 else { return nil }
        let usedLatitudes = indices.map { lat.values[$0] }
        guard let latMin = usedLatitudes.min(), let latMax = usedLatitudes.max() else { return nil }
        let sharedAxis0 = lon.times == lat.times
        let usedLongitudes = indices.map { index in
            sharedAxis0 ? lon.values[index] : (lon.value(at: lat.times[index]) ?? 0)
        }
        guard let lonMin = usedLongitudes.min(), let lonMax = usedLongitudes.max() else { return nil }
        let latitude0 = (latMin + latMax) / 2
        let longitude0 = (lonMin + lonMax) / 2
        basis = Basis(
            latitude0: latitude0, longitude0: longitude0, cosLat: cos(latitude0 * .pi / 180),
            rotation: -rotationDegrees * .pi / 180)  // clockwise on screen (y-up maths rotates anticlockwise)
        var projected: [(x: Double, y: Double)] = []
        projected.reserveCapacity(indices.count)
        for position in usedLatitudes.indices {
            projected.append(basis.project(latitude: usedLatitudes[position], longitude: usedLongitudes[position]))
        }
        points = projected
        times = indices.map { lat.times[$0] }
        segments = Self.runs(of: indices)
        minX = projected.map(\.x).min() ?? 0
        maxX = projected.map(\.x).max() ?? 1
        minY = projected.map(\.y).min() ?? 0
        maxY = projected.map(\.y).max() ?? 1
    }

    /// Where the kept samples ran on from one another, as ranges into the kept ones.
    static func runs(of indices: [Int]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var start = 0
        for position in 1...indices.count
        where position == indices.count || indices[position] != indices[position - 1] + 1 {
            result.append(start..<position)
            start = position
        }
        return result
    }

    /// The projection a track map object draws with, so the editor and the renderer agree about
    /// where a coordinate lands — including the reference-lap framing, which moves every point.
    public init?(session: TelemetrySession, params: TrackMapParams) {
        self.init(
            session: session, rotationDegrees: params.rotation,
            range: params.trace == .referenceLap ? Sectors.referenceLap(in: session).flatMap(\.timeRange) : nil,
            onTrack: params.trace == .trackOnly ? TrackExtent.onTrack(in: session) : nil)
    }

    public func point(latitude: Double, longitude: Double, in bounds: CGRect) -> CGPoint {
        let p = basis.project(latitude: latitude, longitude: longitude)
        return point(x: p.x, y: p.y, in: bounds)
    }

    /// Maps projected coordinates into `bounds` with 8% padding, preserving aspect; north is up.
    func point(x: Double, y: Double, in bounds: CGRect) -> CGPoint {
        let fit = self.fit(in: bounds)
        return CGPoint(x: fit.originX + (x - minX) * fit.scale, y: fit.originY + (maxY - y) * fit.scale)
    }

    /// Where a point on the drawn map is on the Earth — the inverse of `point(latitude:longitude:)`.
    ///
    /// This is what lets the start/finish line be placed by pointing at the map instead of typed as
    /// two six-decimal numbers.
    public func coordinate(at point: CGPoint, in bounds: CGRect) -> (latitude: Double, longitude: Double) {
        let fit = self.fit(in: bounds)
        let x = (point.x - fit.originX) / fit.scale + minX
        let y = maxY - (point.y - fit.originY) / fit.scale
        return basis.unproject(x: x, y: y)
    }

    /// Scale and origin of the trace inside `bounds`, shared by the forward and inverse mappings so
    /// neither can be changed without the other.
    private struct Fit {
        let scale: Double
        let originX: Double
        let originY: Double
    }

    private func fit(in bounds: CGRect) -> Fit {
        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)
        let padding = 0.08
        let scale = min(bounds.width * (1 - 2 * padding) / spanX, bounds.height * (1 - 2 * padding) / spanY)
        return Fit(
            scale: scale, originX: bounds.minX + (bounds.width - spanX * scale) / 2,
            originY: bounds.minY + (bounds.height - spanY * scale) / 2)
    }

    /// Which way the car was going at the trace point nearest `point`, in compass degrees.
    ///
    /// A start/finish line with no heading is crossed in whatever direction the track runs there —
    /// that is what `LapDetector` does — so the editor must draw it square to the trace rather than
    /// square to nothing.
    public func traceHeading(nearest point: CGPoint, in bounds: CGRect) -> Double? {
        guard points.count > 1 else { return nil }
        var best = 0
        var bestDistance = Double.infinity
        for index in points.indices {
            let drawn = self.point(x: points[index].x, y: points[index].y, in: bounds)
            let distance = hypot(drawn.x - point.x, drawn.y - point.y)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        let after = min(best + 1, points.count - 1)
        let before = after == best ? best - 1 : best
        let start = basis.unproject(x: points[before].x, y: points[before].y)
        let end = basis.unproject(x: points[after].x, y: points[after].y)
        return TrackMapEditing.bearing(from: start, to: end, cosLat: basis.cosLat)
    }
}

extension Lap {
    /// The lap as a closed time range, for restricting a projection to it.
    var timeRange: ClosedRange<Double>? {
        guard let end, end > start else { return nil }
        return start...end
    }
}
