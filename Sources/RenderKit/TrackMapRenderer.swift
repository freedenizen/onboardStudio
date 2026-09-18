import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Draws the whole session's GPS trace (cached) and a dot at the current position.
public struct TrackMapRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: TrackMapParams
    let projection: TrackProjection?

    public init(context: ObjectContext, params: TrackMapParams) {
        self.context = context
        self.params = params
        projection = context.sampler.flatMap { TrackProjection(session: $0.session, rotationDegrees: params.rotation) }
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard let projection, rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        let key = context.cacheKey("trackmap|\(params.hashValue)", size: size)
        if let trace = context.cache.image(
            for: key, size: rect.size,
            draw: { traceContext, traceSize in
                drawTrace(in: traceContext, size: traceSize, projection: projection)
            })
        {
            context.cache.drawImage(trace, in: rect, context: cg)
        }
        guard let sample = context.sample(at: time), let lat = sample[.latitude], let lon = sample[.longitude] else {
            return
        }
        let point = projection.point(latitude: lat, longitude: lon, in: CGRect(origin: .zero, size: rect.size))
        let dot = CGPoint(x: rect.minX + point.x, y: rect.minY + point.y)
        let radius = params.dotRadius * max(0.5, min(rect.width, rect.height) / 300)
        cg.setFillColor(params.dotColor.cgColor)
        cg.fillEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: 2 * radius, height: 2 * radius))
        cg.setStrokeColor(RGBAColor.black.cgColor)
        cg.setLineWidth(max(1, radius * 0.25))
        cg.strokeEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: 2 * radius, height: 2 * radius))
    }

    func drawTrace(in cg: CGContext, size: CGSize, projection: TrackProjection) {
        let bounds = CGRect(origin: .zero, size: size)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(
                bounds, radius: min(size.width, size.height) * 0.05, color: params.backgroundColor.cgColor)
        }
        let points = projection.points.map { projection.point(x: $0.x, y: $0.y, in: bounds) }
        guard points.count > 1 else { return }
        cg.setStrokeColor(params.lineColor.cgColor)
        cg.setLineWidth(params.lineWidth * max(0.5, min(size.width, size.height) / 300))
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        cg.move(to: points[0])
        for point in points.dropFirst() { cg.addLine(to: point) }
        cg.strokePath()
    }
}

/// Local equirectangular projection of the session's positions, rotated, with bounds for fitting.
struct TrackProjection: Sendable {
    struct Basis: Sendable {
        let latitude0: Double
        let longitude0: Double
        let cosLat: Double
        let rotation: Double

        func project(latitude: Double, longitude: Double) -> (x: Double, y: Double) {
            let x = (longitude - longitude0) * cosLat
            let y = latitude - latitude0
            return (x * cos(rotation) - y * sin(rotation), x * sin(rotation) + y * cos(rotation))
        }
    }

    let basis: Basis
    let points: [(x: Double, y: Double)]
    let minX: Double
    let maxX: Double
    let minY: Double
    let maxY: Double

    init?(session: TelemetrySession, rotationDegrees: Double) {
        guard let lat = session[.latitude], let lon = session[.longitude], lat.count > 1,
            let latMin = lat.minValue, let latMax = lat.maxValue, let lonMin = lon.minValue,
            let lonMax = lon.maxValue
        else { return nil }
        let latitude0 = (latMin + latMax) / 2
        let longitude0 = (lonMin + lonMax) / 2
        basis = Basis(
            latitude0: latitude0, longitude0: longitude0, cosLat: cos(latitude0 * .pi / 180),
            rotation: rotationDegrees * .pi / 180)
        var projected: [(x: Double, y: Double)] = []
        projected.reserveCapacity(lat.count)
        // Compare the time axes once; doing it per sample made this quadratic on long sessions.
        let sharedAxis = lon.times == lat.times
        for (index, time) in lat.times.enumerated() {
            let longitude = sharedAxis ? lon.values[index] : (lon.value(at: time) ?? longitude0)
            projected.append(basis.project(latitude: lat.values[index], longitude: longitude))
        }
        points = projected
        minX = projected.map(\.x).min() ?? 0
        maxX = projected.map(\.x).max() ?? 1
        minY = projected.map(\.y).min() ?? 0
        maxY = projected.map(\.y).max() ?? 1
    }

    func point(latitude: Double, longitude: Double, in bounds: CGRect) -> CGPoint {
        let p = basis.project(latitude: latitude, longitude: longitude)
        return point(x: p.x, y: p.y, in: bounds)
    }

    /// Maps projected coordinates into `bounds` with 8% padding, preserving aspect; north is up.
    func point(x: Double, y: Double, in bounds: CGRect) -> CGPoint {
        let spanX = max(maxX - minX, 1e-9)
        let spanY = max(maxY - minY, 1e-9)
        let padding = 0.08
        let scale = min(bounds.width * (1 - 2 * padding) / spanX, bounds.height * (1 - 2 * padding) / spanY)
        let drawnWidth = spanX * scale
        let drawnHeight = spanY * scale
        let originX = bounds.minX + (bounds.width - drawnWidth) / 2
        let originY = bounds.minY + (bounds.height - drawnHeight) / 2
        return CGPoint(x: originX + (x - minX) * scale, y: originY + (maxY - y) * scale)
    }
}
