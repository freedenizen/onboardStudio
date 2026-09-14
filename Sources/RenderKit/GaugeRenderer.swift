import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A round analogue gauge with ticks, labels, optional red zone, needle and digital readout.
/// Face, ticks and labels are rendered once per size into the cache; only the needle and value
/// are drawn per frame.
public struct GaugeRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: GaugeParams

    public init(context: ObjectContext, params: GaugeParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        let geometry = Geometry(rect: rect)
        cg.setAlpha(context.opacity)

        let key = context.cacheKey("gauge|\(params.hashValue)", size: size)
        if let face = context.cache.image(
            for: key, size: rect.size,
            draw: { faceContext, faceSize in
                drawFace(in: faceContext, geometry: Geometry(rect: CGRect(origin: .zero, size: faceSize)))
            })
        {
            context.cache.drawImage(face, in: rect, context: cg)
        }

        let sample = context.sample(at: time)
        let raw = ChannelValue.display(params.channel, in: sample, speedUnit: params.speedUnit)
        let value = raw.map { $0 / params.valueDivisor }
        drawNeedle(value: value ?? params.minValue, in: cg, geometry: geometry)
        if params.showValue {
            let text = value.map { ValueFormatting.format($0, decimals: params.decimals) } ?? "--"
            // Readout sits in the bottom gap of the sweep, below the end-of-scale labels.
            let style = TextDrawing.Style.mono(geometry.radius * 0.22, color: params.textColor)
            TextDrawing.drawCentered(
                text, at: CGPoint(x: geometry.center.x, y: geometry.center.y + geometry.radius * 0.64), style: style,
                in: cg)
            let unit = unitText
            if !unit.isEmpty {
                let unitStyle = TextDrawing.Style(
                    pointSize: geometry.radius * 0.12, color: params.textColor, weightBold: false)
                TextDrawing.drawCentered(
                    unit, at: CGPoint(x: geometry.center.x, y: geometry.center.y + geometry.radius * 0.83),
                    style: unitStyle,
                    in: cg)
            }
        }
    }

    var unitText: String {
        ChannelValue.role(params.channel) == .speed ? params.speedUnit.rawValue : params.unitLabel
    }

    // MARK: - Geometry

    struct Geometry {
        let center: CGPoint
        let radius: Double

        init(rect: CGRect) {
            radius = min(rect.width, rect.height) / 2
            center = CGPoint(x: rect.midX, y: rect.midY)
        }

        func point(angle: Double, radius r: Double) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r)
        }
    }

    /// Angle (radians, screen coordinates: 0 = right, increasing clockwise) for a channel value.
    func angle(for value: Double) -> Double {
        let span = max(params.maxValue - params.minValue, 0.000_001)
        let fraction = min(max((value - params.minValue) / span, 0), 1)
        let sweep = params.sweep * .pi / 180
        // Arc is centred on "up" (−90°) rotated by params.rotation; gap at the bottom for 270°.
        let start = -Double.pi / 2 - sweep / 2 + params.rotation * .pi / 180
        return start + fraction * sweep
    }

    // MARK: - Static face

    func drawFace(in cg: CGContext, geometry: Geometry) {
        let r = geometry.radius
        cg.setFillColor(params.faceColor.cgColor)
        cg.fillEllipse(in: CGRect(x: geometry.center.x - r, y: geometry.center.y - r, width: 2 * r, height: 2 * r))
        cg.setStrokeColor(RGBAColor(red: 1, green: 1, blue: 1, alpha: 0.35).cgColor)
        cg.setLineWidth(max(1, r * 0.02))
        cg.strokeEllipse(
            in: CGRect(
                x: geometry.center.x - r * 0.98, y: geometry.center.y - r * 0.98, width: 2 * r * 0.98,
                height: 2 * r * 0.98))

        if let redline = params.redlineFrom, redline < params.maxValue {
            cg.setStrokeColor(params.redlineColor.cgColor)
            cg.setLineWidth(r * 0.08)
            cg.addArc(
                center: geometry.center, radius: r * 0.82, startAngle: angle(for: redline),
                endAngle: angle(for: params.maxValue), clockwise: false)
            cg.strokePath()
        }

        let major = max(params.majorTick, 0.000_001)
        let minor = max(params.minorTick, 0.000_001)
        var value = params.minValue
        var guardCount = 0
        while value <= params.maxValue + minor * 0.01, guardCount < 500 {
            let isMajor =
                abs((value - params.minValue).truncatingRemainder(dividingBy: major)) < minor * 0.01
                || abs((value - params.minValue).truncatingRemainder(dividingBy: major) - major) < minor * 0.01
            let a = angle(for: value)
            let inner = geometry.point(angle: a, radius: r * (isMajor ? 0.72 : 0.80))
            let outer = geometry.point(angle: a, radius: r * 0.88)
            cg.setStrokeColor(params.textColor.cgColor)
            cg.setLineWidth(r * (isMajor ? 0.03 : 0.015))
            cg.move(to: inner)
            cg.addLine(to: outer)
            cg.strokePath()
            if isMajor {
                let labelPoint = geometry.point(angle: a, radius: r * 0.58)
                let label = ValueFormatting.format(value, decimals: 0)
                TextDrawing.drawCentered(
                    label, at: labelPoint, style: TextDrawing.Style(pointSize: r * 0.13, color: params.textColor),
                    in: cg)
            }
            value += minor
            guardCount += 1
        }

        if !params.title.isEmpty {
            let style = TextDrawing.Style(pointSize: r * 0.14, color: params.textColor)
            TextDrawing.drawCentered(
                params.title, at: CGPoint(x: geometry.center.x, y: geometry.center.y - r * 0.32), style: style, in: cg)
        }
    }

    // MARK: - Needle

    func drawNeedle(value: Double, in cg: CGContext, geometry: Geometry) {
        let r = geometry.radius
        let a = angle(for: value)
        let tip = geometry.point(angle: a, radius: r * 0.86)
        let tail = geometry.point(angle: a + .pi, radius: r * 0.15)
        let left = geometry.point(angle: a + .pi / 2, radius: r * 0.03)
        let right = geometry.point(angle: a - .pi / 2, radius: r * 0.03)
        cg.setFillColor(params.needleColor.cgColor)
        cg.move(to: tip)
        cg.addLine(to: CGPoint(x: left.x + (tail.x - geometry.center.x), y: left.y + (tail.y - geometry.center.y)))
        cg.addLine(to: CGPoint(x: right.x + (tail.x - geometry.center.x), y: right.y + (tail.y - geometry.center.y)))
        cg.closePath()
        cg.fillPath()
        let hub = r * 0.08
        cg.setFillColor(params.textColor.cgColor)
        cg.fillEllipse(
            in: CGRect(x: geometry.center.x - hub, y: geometry.center.y - hub, width: 2 * hub, height: 2 * hub))
    }
}
