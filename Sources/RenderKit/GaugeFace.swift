import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The static part of a gauge: face, zone bands, arc track, ticks and labels. Rendered once per
/// size into the cache by `GaugeRenderer.draw`.
extension GaugeRenderer {
    // MARK: - Static face

    func drawFace(in cg: CGContext, geometry: Geometry) {
        let r = geometry.radius
        if let faceImage {
            let square = CGRect(x: geometry.center.x - r, y: geometry.center.y - r, width: 2 * r, height: 2 * r)
            let scale = min(square.width / Double(faceImage.width), square.height / Double(faceImage.height))
            let w = Double(faceImage.width) * scale
            let h = Double(faceImage.height) * scale
            let drawRect = CGRect(x: square.midX - w / 2, y: square.midY - h / 2, width: w, height: h)
            cg.saveGState()
            cg.translateBy(x: 0, y: drawRect.maxY + drawRect.minY)
            cg.scaleBy(x: 1, y: -1)
            cg.interpolationQuality = .high
            cg.draw(faceImage.image, in: drawRect)
            cg.restoreGState()
        } else if params.showFace {
            cg.setFillColor(params.faceColor.cgColor)
            cg.fillEllipse(in: CGRect(x: geometry.center.x - r, y: geometry.center.y - r, width: 2 * r, height: 2 * r))
            cg.setStrokeColor(RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.35).cgColor)
            cg.setLineWidth(max(1, r * 0.02))
            cg.strokeEllipse(
                in: CGRect(
                    x: geometry.center.x - r * 0.98, y: geometry.center.y - r * 0.98, width: 2 * r * 0.98,
                    height: 2 * r * 0.98))
        }

        if params.zoneTargets.face { drawZoneBands(in: cg, geometry: geometry) }
        if params.style == .arc { drawArcTrack(in: cg, geometry: geometry) }
        drawTicks(in: cg, geometry: geometry)

        if !params.title.isEmpty {
            let style = TextDrawing.Style(pointSize: r * 0.14, color: params.textColor)
            TextDrawing.drawCentered(
                params.title, at: CGPoint(x: geometry.center.x, y: geometry.center.y - r * 0.32), style: style, in: cg)
        }
    }

    func drawZoneBands(in cg: CGContext, geometry: Geometry) {
        let r = geometry.radius
        let bandRadius = r * (params.ticks.outerRadius - 0.06)
        cg.setLineWidth(r * 0.08)
        let span = max(params.maxValue - params.minValue, 0.000_001)
        if params.zoneTargets.gradient {
            // Paint the scale in small steps so colour blends show.
            let steps = 180
            var previous: RGBAColor?
            var runStart = params.minValue
            for step in 0...steps {
                let value = params.minValue + span * Double(step) / Double(steps)
                let color = zoneColor(at: value)
                if color != previous || step == steps {
                    if let previous, previous.alpha > 0 {
                        strokeArc(runStart...value, radius: bandRadius, color: previous, in: cg, geometry: geometry)
                    }
                    runStart = value
                    previous = color
                }
            }
        } else {
            for zone in params.zones where zone.from < params.maxValue {
                let end = min(zone.to ?? params.maxValue, params.maxValue)
                guard end > zone.from else { continue }
                strokeArc(zone.from...end, radius: bandRadius, color: zone.color, in: cg, geometry: geometry)
            }
        }
    }

    func strokeArc(_ range: ClosedRange<Double>, radius: Double, color: RGBAColor, in cg: CGContext, geometry: Geometry)
    {
        cg.setStrokeColor(color.cgColor)
        cg.addArc(
            center: geometry.center, radius: radius, startAngle: angle(for: range.lowerBound),
            endAngle: angle(for: range.upperBound), clockwise: params.counterClockwise)
        cg.strokePath()
    }

    var arcRadius: Double { params.ticks.outerRadius - params.arcWidth / 2 - 0.02 }

    func drawArcTrack(in cg: CGContext, geometry: Geometry) {
        let r = geometry.radius
        cg.setLineWidth(r * params.arcWidth)
        cg.setLineCap(.butt)
        strokeArc(
            params.minValue...params.maxValue, radius: r * arcRadius, color: params.arcTrackColor, in: cg,
            geometry: geometry)
    }

    func drawTicks(in cg: CGContext, geometry: Geometry) {
        let r = geometry.radius
        let ticks = params.ticks
        let major = max(params.majorTick, 0.000_001)
        let minor = max(params.minorTick, 0.000_001)
        let span = max(params.maxValue - params.minValue, 0.000_001)
        let labelStyle = TextDrawing.Style(pointSize: r * ticks.labelScale, color: params.textColor)

        // Decide which major labels fit: skip every k-th when neighbours would overlap.
        var labelSkip = 1
        if ticks.showLabels, ticks.declutter {
            let majorCount = Int((span / major).rounded(.down))
            let sweep = min(max(params.sweep, 1), 360) * .pi / 180
            let stepAngle = sweep * major / span
            let chord = 2 * r * ticks.labelRadius * sin(min(stepAngle / 2, .pi / 2))
            var widest = 0.0
            for index in 0...max(majorCount, 1) {
                let value = params.minValue + Double(index) * major
                widest = max(widest, TextDrawing.size(of: label(for: value), style: labelStyle).width)
            }
            if chord > 0, widest * 1.15 > chord {
                labelSkip = Int((widest * 1.15 / chord).rounded(.up))
            }
        }

        var value = params.minValue
        var index = 0
        while value <= params.maxValue + minor * 0.01, index < 2000 {
            let remainder = (value - params.minValue).truncatingRemainder(dividingBy: major)
            let isMajor = abs(remainder) < minor * 0.01 || abs(remainder - major) < minor * 0.01
            let a = angle(for: value)
            let color = params.zoneTargets.marks ? (zoneColor(at: value) ?? params.textColor) : params.textColor
            if (isMajor && ticks.showMajor) || (!isMajor && ticks.showMinor) {
                let length = isMajor ? ticks.majorLength : ticks.minorLength
                let inner = geometry.point(angle: a, radius: r * (ticks.outerRadius - length))
                let outer = geometry.point(angle: a, radius: r * ticks.outerRadius)
                cg.setStrokeColor(color.cgColor)
                cg.setLineWidth(r * (isMajor ? 0.03 : 0.015))
                cg.move(to: inner)
                cg.addLine(to: outer)
                cg.strokePath()
            }
            // On a full circle the last label would sit on top of the first.
            let duplicatesFirst = params.sweep >= 360 && value >= params.maxValue - minor * 0.01
            if isMajor, ticks.showLabels, !duplicatesFirst {
                let majorIndex = Int(((value - params.minValue) / major).rounded())
                if majorIndex % labelSkip == 0 {
                    var style = labelStyle
                    style.color = color
                    let labelPoint = geometry.point(angle: a, radius: r * ticks.labelRadius)
                    TextDrawing.drawCentered(label(for: value), at: labelPoint, style: style, in: cg)
                }
            }
            value += minor
            index += 1
        }
    }

    func label(for value: Double) -> String {
        ValueFormatting.format(value, decimals: params.ticks.labelDecimals)
    }
}
