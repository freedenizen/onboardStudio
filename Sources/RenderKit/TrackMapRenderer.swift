import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A second data input shown as another dot on the same map.
public struct SecondVehicle: Sendable {
    public let sampler: TelemetrySampler
    public let sync: SyncSettings

    public init(sampler: TelemetrySampler, sync: SyncSettings) {
        self.sampler = sampler
        self.sync = sync
    }
}

/// Draws the whole session's GPS trace (cached, optionally over map imagery) and a dot at the
/// current position; a second vehicle's position can be shown as another dot.
public struct TrackMapRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: TrackMapParams
    public let second: SecondVehicle?
    public let background: MapBackground?
    let projection: TrackProjection?
    /// Sector colouring, ticks and corner numbers, worked out once. All of it is empty unless
    /// the matching option is on, so a plain map costs exactly what it used to.
    let marks: TrackMapMarks

    public init(
        context: ObjectContext, params: TrackMapParams, second: SecondVehicle? = nil, background: MapBackground? = nil
    ) {
        self.context = context
        self.params = params
        self.second = second
        self.background = background
        let session = context.sampler?.session
        let built = session.flatMap { TrackProjection(session: $0, params: params) }
        projection = built
        marks = session.map { TrackMapMarks(session: $0, params: params, projection: built) } ?? TrackMapMarks()
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard let projection, rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        let key = context.cacheKey(
            "trackmap|\(params.hashValue)|\(background?.request.hashValue ?? 0)", size: size)
        if let trace = context.cache.image(
            for: key, size: rect.size,
            draw: { traceContext, traceSize in
                drawTrace(in: traceContext, size: traceSize, projection: projection)
            })
        {
            context.cache.drawImage(trace, in: rect, context: cg)
        }
        let bounds = CGRect(origin: .zero, size: rect.size)
        let radius = params.dotRadius * max(0.5, min(rect.width, rect.height) / 300)
        if let second, let lat = second.sampler.sample(at: second.sync.inputTime(forProjectTime: time))[.latitude],
            let lon = second.sampler.sample(at: second.sync.inputTime(forProjectTime: time))[.longitude]
        {
            let point = projection.point(latitude: lat, longitude: lon, in: bounds)
            drawDot(at: held(point, inside: rect, radius: radius), radius: radius, color: params.secondDotColor, in: cg)
        }
        guard let sample = context.sample(at: time), let lat = sample[.latitude], let lon = sample[.longitude] else {
            return
        }
        let point = projection.point(latitude: lat, longitude: lon, in: bounds)
        drawDot(at: held(point, inside: rect, radius: radius), radius: radius, color: params.dotColor, in: cg)
    }

    /// The dot's place in the object, kept inside it.
    ///
    /// The outline need not cover everywhere the car went — a reference-lap map draws one lap, and
    /// a track-only map leaves the pit lane out — so a car that is off the drawn part projects
    /// outside the object. The dot is not part of the cached trace image and so is not clipped by
    /// it: unheld, it would be drawn loose over the video. Held at the edge it reads as what it
    /// is, which is the car being somewhere the map does not show.
    func held(_ point: CGPoint, inside rect: CGRect, radius: Double) -> CGPoint {
        CGPoint(
            x: min(max(rect.minX + point.x, rect.minX + radius), rect.maxX - radius),
            y: min(max(rect.minY + point.y, rect.minY + radius), rect.maxY - radius))
    }

    func drawDot(at dot: CGPoint, radius: Double, color: RGBAColor, in cg: CGContext) {
        let box = CGRect(x: dot.x - radius, y: dot.y - radius, width: 2 * radius, height: 2 * radius)
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: box)
        cg.setStrokeColor(RGBAColor.black.cgColor)
        cg.setLineWidth(max(1, radius * 0.25))
        cg.strokeEllipse(in: box)
    }

    func drawTrace(in cg: CGContext, size: CGSize, projection: TrackProjection) {
        let bounds = CGRect(origin: .zero, size: size)
        let radius = min(size.width, size.height) * 0.05
        if let background {
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: bounds, cornerWidth: radius, cornerHeight: radius, transform: nil))
            cg.clip()
            drawBackground(background, in: cg, bounds: bounds, projection: projection)
            cg.restoreGState()
        }
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(bounds, radius: radius, color: params.backgroundColor.cgColor)
        }
        let points = projection.points.map { projection.point(x: $0.x, y: $0.y, in: bounds) }
        guard points.count > 1 else { return }
        let scale = max(0.5, min(size.width, size.height) / 300)
        cg.setLineWidth(params.lineWidth * scale)
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        for run in outlineRuns(segments: projection.segments, count: points.count) {
            cg.setStrokeColor(colour(ofSector: run.sector).cgColor)
            cg.move(to: points[run.range.lowerBound])
            for index in (run.range.lowerBound + 1)..<run.range.upperBound { cg.addLine(to: points[index]) }
            cg.strokePath()
        }
        let labelSize = max(6, min(size.width, size.height) * params.labelScale)
        if params.showSectorTicks {
            for (index, boundary) in marks.boundaries.enumerated() {
                drawTick(
                    boundary, number: index + 2, in: cg, bounds: bounds, projection: projection,
                    scale: scale, labelSize: labelSize)
            }
        }
        if params.showCornerNumbers {
            for (index, corner) in marks.corners.enumerated() {
                let point = projection.point(latitude: corner.latitude, longitude: corner.longitude, in: bounds)
                label(marks.cornerLabel(index), at: point, size: labelSize, in: cg)
            }
        }
    }

    /// Runs of consecutive trace points that share a sector, so the outline is stroked once per
    /// colour instead of once per point.
    ///
    /// Sector colours may not run across a break in the trace: `segments` are the stretches the
    /// car actually drove without leaving, and joining two of them would rule a line straight
    /// across the circuit from the pit entry to the pit exit. So each segment is split by sector
    /// rather than the whole trace being split and the breaks forgotten.
    func outlineRuns(segments: [Range<Int>], count: Int) -> [(range: Range<Int>, sector: Int)] {
        let drawable = segments.filter { $0.count > 1 }
        guard params.colorBySector, marks.sectorOfPoint.count == count else {
            return drawable.map { ($0, -1) }
        }
        var runs: [(range: Range<Int>, sector: Int)] = []
        for segment in drawable {
            var start = segment.lowerBound
            for index in (segment.lowerBound + 1)...segment.upperBound {
                // Runs overlap by a point so the colours meet rather than leaving a gap — but
                // never across a segment's end, where the gap is the point.
                let ended = index == segment.upperBound || marks.sectorOfPoint[index] != marks.sectorOfPoint[start]
                guard ended else { continue }
                if index - start > 1 { runs.append((start..<index, marks.sectorOfPoint[start] ?? -1)) }
                start = index - 1
            }
        }
        return runs.isEmpty ? drawable.map { ($0, -1) } : runs
    }

    /// The colour for a sector, or the plain line colour for `-1` (no sector, or colouring off).
    func colour(ofSector sector: Int) -> RGBAColor {
        guard sector >= 0, !params.sectorColors.isEmpty else { return params.lineColor }
        return params.sectorColors[sector % params.sectorColors.count]
    }

    // A line across the track at a sector boundary, with the number of the sector it starts.
    // swiftlint:disable:next function_parameter_count
    func drawTick(
        _ boundary: LapComparison.LapPoint, number: Int, in cg: CGContext, bounds: CGRect,
        projection: TrackProjection, scale: Double, labelSize: Double
    ) {
        let centre = projection.point(latitude: boundary.latitude, longitude: boundary.longitude, in: bounds)
        guard let travel = direction(of: boundary, projection: projection, bounds: bounds) else { return }
        let dx = travel.x
        let dy = travel.y
        let half = max(4, 7 * scale)
        cg.setStrokeColor(params.labelColor.cgColor)
        cg.setLineWidth(max(1, params.lineWidth * scale * 0.8))
        cg.move(to: CGPoint(x: centre.x - dy * half, y: centre.y + dx * half))
        cg.addLine(to: CGPoint(x: centre.x + dy * half, y: centre.y - dx * half))
        cg.strokePath()
        label(
            "S\(number)", at: labelPoint(from: centre, across: (dy, -dx), by: half * 2.2, in: bounds),
            size: labelSize, in: cg)
    }

    /// The direction of travel at a boundary, as a unit vector in map space — which already
    /// includes the map's rotation, so the tick can simply be drawn square to it.
    ///
    /// The longitude step is divided by `cosLat` because the projection multiplies it back: a
    /// degree of longitude is a shorter distance away from the equator. Without that the
    /// projected direction comes out as `atan(tan(heading) · cosLat)`, which is 13° off a
    /// diagonal heading at Silverstone's latitude and leaves the tick square to nothing.
    func direction(of boundary: LapComparison.LapPoint, projection: TrackProjection, bounds: CGRect)
        -> (x: Double, y: Double)?
    {
        let step = 1e-4
        let centre = projection.point(latitude: boundary.latitude, longitude: boundary.longitude, in: bounds)
        let ahead = projection.point(
            latitude: boundary.latitude + cos(boundary.headingDegrees * .pi / 180) * step,
            longitude: boundary.longitude + sin(boundary.headingDegrees * .pi / 180) * step
                / max(projection.basis.cosLat, 1e-9),
            in: bounds)
        let dx = ahead.x - centre.x
        let dy = ahead.y - centre.y
        let length = hypot(dx, dy)
        guard length > 0 else { return nil }
        return (dx / length, dy / length)
    }

    /// Which end of a tick to write its number at: the one towards the middle of the map.
    ///
    /// A boundary on the outside of the circuit would otherwise push its label off the object —
    /// the map is framed to the trace, so there is no margin out there, while the middle of a
    /// circuit is the one place reliably empty.
    func labelPoint(
        from centre: CGPoint, across normal: (x: Double, y: Double), by distance: Double, in bounds: CGRect
    ) -> CGPoint {
        let towards = CGPoint(x: centre.x + normal.x * distance, y: centre.y + normal.y * distance)
        let away = CGPoint(x: centre.x - normal.x * distance, y: centre.y - normal.y * distance)
        let middle = CGPoint(x: bounds.midX, y: bounds.midY)
        func gap(_ point: CGPoint) -> Double { hypot(point.x - middle.x, point.y - middle.y) }
        return gap(towards) <= gap(away) ? towards : away
    }

    /// Centred text with a black surround, so a number stays readable over map imagery.
    func label(_ string: String, at point: CGPoint, size: Double, in cg: CGContext) {
        let style = context.styled(TextDrawing.Style(pointSize: size, color: params.labelColor))
        var back = style
        back.color = .black
        let offset = max(1, size * 0.08)
        let origin = CGPoint(x: point.x, y: point.y - size * 0.6)
        for dx in [-offset, 0, offset] {
            for dy in [-offset, 0, offset] where dx != 0 || dy != 0 {
                TextDrawing.draw(
                    string, at: CGPoint(x: origin.x + dx, y: origin.y + dy), alignment: .center, style: back, in: cg)
            }
        }
        TextDrawing.draw(string, at: origin, alignment: .center, style: style, in: cg)
    }

    /// Places the map image so its geography lines up with the projected trace: a similarity
    /// transform (both mappings are locally conformal) fitted on the centre and a point due north.
    func drawBackground(_ background: MapBackground, in cg: CGContext, bounds: CGRect, projection: TrackProjection) {
        let lat0 = projection.basis.latitude0
        let lon0 = projection.basis.longitude0
        let step = 0.001
        let imageA = background.point(latitude: lat0, longitude: lon0)
        let imageB = background.point(latitude: lat0 + step, longitude: lon0)
        let boundsA = projection.point(latitude: lat0, longitude: lon0, in: bounds)
        let boundsB = projection.point(latitude: lat0 + step, longitude: lon0, in: bounds)
        let imageSpan = hypot(imageB.x - imageA.x, imageB.y - imageA.y)
        let boundsSpan = hypot(boundsB.x - boundsA.x, boundsB.y - boundsA.y)
        guard imageSpan > 0, boundsSpan > 0 else { return }
        let scale = boundsSpan / imageSpan
        let angle =
            atan2(boundsB.y - boundsA.y, boundsB.x - boundsA.x) - atan2(imageB.y - imageA.y, imageB.x - imageA.x)
        cg.saveGState()
        cg.translateBy(x: boundsA.x, y: boundsA.y)
        cg.rotate(by: angle)
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: -imageA.x, y: -imageA.y)
        // The context is flipped (y down); undo that for the image so it is not drawn upside down.
        let height = CGFloat(background.image.height)
        cg.translateBy(x: 0, y: height)
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .high
        cg.draw(background.image, in: CGRect(x: 0, y: 0, width: CGFloat(background.image.width), height: height))
        cg.restoreGState()
    }
}

/// Sector colouring, sector boundaries and corner apexes for a track map, worked out once when
/// the renderer is built and reused for every frame the cached trace image serves.
///
/// Everything here is empty unless the matching option is on: nothing about a plain outline map
/// got slower for options nobody switched on.
struct TrackMapMarks: Sendable {
    /// The sector each projected trace point falls in, aligned with `TrackProjection.points`.
    var sectorOfPoint: [Int?] = []
    /// Each sector boundary on the reference lap, in order. One shorter than the sector count:
    /// the start/finish line is where the first sector begins and is not a boundary.
    var boundaries: [LapComparison.LapPoint] = []
    /// Each corner's apex on the reference lap, in the order they are driven.
    var corners: [LapComparison.LapPoint] = []
    /// What the circuit calls them, if the driver has said. Shorter than `corners` is fine: the
    /// rest fall back to their position round the lap.
    var labels: [String] = []

    /// The label for the `index`-th corner of the lap.
    ///
    /// Falling back to `index + 1` is a **count**, not the circuit's own number — Sonoma runs
    /// 3, 3a, 4, 4a and a sequential count is wrong there. It is the honest answer until
    /// somebody says otherwise, and the inspector is where they say it.
    func cornerLabel(_ index: Int) -> String {
        guard index < labels.count, !labels[index].isEmpty else { return "\(index + 1)" }
        return labels[index]
    }

    init() {}

    init(session: TelemetrySession, params: TrackMapParams, projection: TrackProjection?) {
        guard let reference = Sectors.referenceLap(in: session) else { return }
        if params.colorBySector, let layout = session.sectors?.layout, let projection {
            sectorOfPoint = Sectors.sectorIndices(at: projection.times, layout: layout, session: session)
        }
        if params.showSectorTicks, let layout = session.sectors?.layout {
            boundaries = layout.boundaryDistances.compactMap {
                LapComparison.point(atDistanceInto: reference, metres: $0, session: session)
            }
        }
        if params.showCornerNumbers {
            corners = CornerDetector.corners(of: reference, in: session).compactMap {
                LapComparison.point(atDistanceInto: reference, metres: $0.apexDistance, session: session)
            }
            labels = session.cornerLabels
        }
    }
}
