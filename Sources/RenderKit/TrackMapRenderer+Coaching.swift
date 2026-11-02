import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The coaching reading on the track map (#324): the reference's line, the lap being driven
/// coloured by where it gained and lost, the brake points and slowest points, and the framing
/// that follows the corner in play.
extension TrackMapRenderer {
    /// What this frame draws from the coaching track, worked out once per frame and cheap: the
    /// expensive parts are cached per lap and per corner.
    struct CoachingReading {
        var lap: Lap?
        var analysis: CoachingAnalysis?
        var reference: LapProfile?
        /// The corner being followed, when the map follows corners and one is in play.
        var corner: CornerComparison?
        /// The projection framing the followed corner; `nil` keeps the whole map.
        var projection: TrackProjection?

        /// Distinguishes the cached images: one per lap, and one per followed corner.
        var cacheSuffix: String {
            var parts: [String] = []
            if let lap { parts.append("lap\(lap.number)") }
            if let corner { parts.append("corner\(corner.index)") }
            return parts.joined(separator: "|")
        }
    }

    func coachingReading(at inputTime: Double) -> CoachingReading {
        var reading = CoachingReading()
        guard params.usesCoaching, let track = context.coaching else { return reading }
        reading.reference = params.showReferenceLine || params.showBrakeMarks ? track.reference : nil
        guard params.colorByDelta || params.showBrakeMarks || params.followCorner,
            let (lap, analysis) = track.analysis(atInputTime: inputTime)
        else { return reading }
        reading.lap = lap
        reading.analysis = analysis
        if params.followCorner, let session = context.sampler?.session,
            let moment = track.moment(atInputTime: inputTime, leadSeconds: 3, holdSeconds: 2)
        {
            reading.corner = moment.comparison
            let metrics = moment.comparison.lap
            let margin = 60.0
            let from = lap.start + analysis.lap.elapsed(atDistance: max(0, metrics.phaseStart - margin))
            let to = lap.start + analysis.lap.elapsed(atDistance: metrics.corner.endDistance + margin)
            if to > from {
                reading.projection = TrackProjection(
                    session: session, rotationDegrees: params.rotation, range: from...to)
            }
        }
        return reading
    }

    func drawCoaching(_ reading: CoachingReading, in cg: CGContext, size: CGSize, projection: TrackProjection) {
        let bounds = CGRect(origin: .zero, size: size)
        let scale = max(0.5, min(size.width, size.height) / 300)
        cg.setLineJoin(.round)
        cg.setLineCap(.round)
        if params.showReferenceLine, let reference = reading.reference {
            let points = Self.points(of: reference, projection: projection, bounds: bounds)
            cg.setStrokeColor(params.referenceLineColor.cgColor)
            cg.setLineWidth(max(1, params.lineWidth * scale * 0.7))
            cg.setLineDash(phase: 0, lengths: [6 * scale, 4 * scale])
            stroke(points, in: cg)
            cg.setLineDash(phase: 0, lengths: [])
        }
        if params.colorByDelta, let analysis = reading.analysis {
            cg.setLineWidth(params.lineWidth * scale * 1.1)
            for run in Self.deltaRuns(of: analysis) {
                let points = Self.points(of: analysis.lap, from: run.range, projection: projection, bounds: bounds)
                cg.setStrokeColor((run.isLoss ? params.lossColor : params.gainColor).cgColor)
                stroke(points, in: cg)
            }
        }
        if params.showBrakeMarks {
            let radius = max(3, params.dotRadius * scale * 0.55)
            if let reference = reading.reference, let analysis = reading.analysis {
                for comparison in analysis.corners {
                    drawMarks(
                        comparison.reference, on: reference, color: params.referenceLineColor, radius: radius,
                        projection: projection, bounds: bounds, in: cg)
                    drawMarks(
                        comparison.lap, on: analysis.lap, color: params.lineColor, radius: radius,
                        projection: projection, bounds: bounds, in: cg)
                }
            }
        }
    }

    // Where the brakes went on (a circle) and the slowest point (a square) of one corner.
    // swiftlint:disable:next function_parameter_count
    func drawMarks(
        _ metrics: CornerMetrics, on profile: LapProfile, color: RGBAColor, radius: Double,
        projection: TrackProjection, bounds: CGRect, in cg: CGContext
    ) {
        let apex = metrics.corner.apexDistance
        cg.setFillColor(color.cgColor)
        cg.setStrokeColor(RGBAColor.black.cgColor)
        cg.setLineWidth(max(1, radius * 0.3))
        if let brake = metrics.brakePointMeters, let position = profile.position(atDistance: apex - brake) {
            let point = projection.point(latitude: position.latitude, longitude: position.longitude, in: bounds)
            let box = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
            cg.fillEllipse(in: box)
            cg.strokeEllipse(in: box)
        }
        if let position = profile.position(atDistance: apex + metrics.minimumSpeedMeters) {
            let point = projection.point(latitude: position.latitude, longitude: position.longitude, in: bounds)
            let box = CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius)
            cg.fill(box)
            cg.stroke(box)
        }
    }

    func stroke(_ points: [CGPoint], in cg: CGContext) {
        guard let first = points.first, points.count > 1 else { return }
        cg.move(to: first)
        for point in points.dropFirst() { cg.addLine(to: point) }
        cg.strokePath()
    }

    /// A profile's positions on the map, every grid point.
    static func points(of profile: LapProfile, projection: TrackProjection, bounds: CGRect) -> [CGPoint] {
        points(of: profile, from: 0..<profile.count, projection: projection, bounds: bounds)
    }

    static func points(of profile: LapProfile, from range: Range<Int>, projection: TrackProjection, bounds: CGRect)
        -> [CGPoint]
    {
        guard let latitude = profile.latitude, let longitude = profile.longitude else { return [] }
        return range.clamped(to: 0..<profile.count).map { index in
            projection.point(latitude: latitude[index], longitude: longitude[index], in: bounds)
        }
    }

    /// Where the lap was losing or gaining against the reference: stretches of the lap's grid
    /// where the delta grew or shrank by more than a few hundredths over 20 m. Level stretches
    /// are left to the plain outline.
    struct DeltaRun: Equatable {
        var range: Range<Int>
        var isLoss: Bool
    }

    static func deltaRuns(of analysis: CoachingAnalysis, thresholdSeconds: Double = 0.03) -> [DeltaRun] {
        let lap = analysis.lap
        let delta = analysis.delta
        let window = 10.0
        var runs: [DeltaRun] = []
        var current: DeltaRun?
        for index in 0..<lap.count {
            let distance = lap.distances[index]
            let onReference = delta.distances.last.map { min($0, distance) } ?? distance
            let slope = delta.loss(from: max(0, onReference - window), to: onReference + window)
            let trending = abs(slope) > thresholdSeconds
            let isLoss = slope > 0
            if trending {
                if var run = current, run.isLoss == isLoss {
                    run.range = run.range.lowerBound..<(index + 1)
                    current = run
                } else {
                    if let run = current, run.range.count > 1 { runs.append(run) }
                    current = DeltaRun(range: max(0, index - 1)..<(index + 1), isLoss: isLoss)
                }
            } else if let run = current {
                if run.range.count > 1 { runs.append(run) }
                current = nil
            }
        }
        if let run = current, run.range.count > 1 { runs.append(run) }
        return runs
    }
}
