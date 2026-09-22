import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A round analogue gauge: face (colour or image), zones, ticks, labels, one or two needles or
/// a filled arc, and a digital readout. Everything static is rendered once per size into the
/// cache; only the needle/arc and readout are drawn per frame.
public struct GaugeRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: GaugeParams
    public let faceImage: LoadedImage?

    public init(context: ObjectContext, params: GaugeParams, faceImage: LoadedImage? = nil) {
        self.context = context
        self.params = params
        self.faceImage = faceImage
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        let geometry = Geometry(rect: rect)
        cg.setAlpha(context.opacity)

        let imageTag = faceImage.map { "\($0.width)x\($0.height)" } ?? "none"
        let key = context.cacheKey("gauge|\(params.hashValue)|\(imageTag)", size: size)
        if let face = context.cache.image(
            for: key, size: rect.size,
            draw: { faceContext, faceSize in
                drawFace(in: faceContext, geometry: Geometry(rect: CGRect(origin: .zero, size: faceSize)))
            })
        {
            context.cache.drawImage(face, in: rect, context: cg)
        }

        let value = displayValue(of: params.channel, at: time)
        switch params.style {
        case .needle:
            drawNeedle(value: value ?? params.minValue, color: needleColor(for: value), in: cg, geometry: geometry)
            drawHub(in: cg, geometry: geometry)
        case .dualNeedle:
            let second = params.secondChannel.isEmpty ? nil : displayValue(of: params.secondChannel, at: time)
            if let second {
                drawNeedle(
                    value: second, color: params.secondNeedleColor, in: cg, geometry: geometry, scale: 0.75)
            }
            drawNeedle(value: value ?? params.minValue, color: needleColor(for: value), in: cg, geometry: geometry)
            drawHub(in: cg, geometry: geometry)
        case .arc:
            drawArc(value: value ?? params.minValue, color: needleColor(for: value), in: cg, geometry: geometry)
        }
        if params.showValue {
            drawReadout(value: value, in: cg, geometry: geometry)
        }
    }

    // MARK: - Values

    /// The channel value in display units, divided by `valueDivisor`, smoothed if requested.
    func displayValue(of channel: String, at time: Double) -> Double? {
        let smoothing = params.needle.smoothingSeconds
        guard smoothing > 0, let sampler = context.sampler, let role = ChannelValue.role(channel) else {
            let raw = ChannelValue.display(channel, in: context.sample(at: time), speedUnit: context.speedUnit)
            return raw.map { $0 / params.valueDivisor }
        }
        let steps = 8
        var total = 0.0
        var count = 0
        for step in 0...steps {
            let t = time - smoothing * Double(step) / Double(steps)
            if let v = sampler.value(of: role, at: context.inputTime(t)) {
                total += v
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let mean = total / Double(count)
        let converted = role == .speed ? mean * context.speedUnit.factorFromMetersPerSecond : mean
        return converted / params.valueDivisor
    }

    var unitText: String {
        ChannelValue.role(params.channel) == .speed ? context.speedUnit.rawValue : params.unitLabel
    }

    /// Colour of the needle or arc for `value`, honouring zone colouring.
    func needleColor(for value: Double?) -> RGBAColor {
        guard params.zoneTargets.needle, let value, let zoneColor = zoneColor(at: value) else {
            return params.needleColor
        }
        return zoneColor
    }

    /// The zone colour at `value`: a hard switch at thresholds, or a blend over the 8% of the
    /// scale before each threshold when gradients are on. `nil` outside every zone.
    func zoneColor(at value: Double) -> RGBAColor? {
        let zones = params.zones.sortedByStart
        guard !zones.isEmpty else { return nil }
        let inside = zones.zone(containing: value)
        guard params.zoneTargets.gradient else { return inside?.color }
        let span = max(params.maxValue - params.minValue, 0.000_001)
        let width = span * 0.08
        // Blend towards the next zone's colour as its threshold approaches.
        if let next = zones.first(where: { $0.from > value && $0.from - width <= value }) {
            let fraction = 1 - (next.from - value) / width
            let from =
                inside?.color
                ?? RGBAColor(red: next.color.red, green: next.color.green, blue: next.color.blue, alpha: 0)
            return RGBAColor.lerp(from, next.color, fraction)
        }
        return inside?.color
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
        let sweep = min(max(params.sweep, 1), 360) * .pi / 180
        let rotation = params.rotation * .pi / 180
        // The arc is centred on "up" (−90°) rotated by params.rotation; gap at the bottom for 270°.
        if params.counterClockwise {
            let start = -Double.pi / 2 + sweep / 2 + rotation
            return start - fraction * sweep
        }
        let start = -Double.pi / 2 - sweep / 2 + rotation
        return start + fraction * sweep
    }

    // MARK: - Needle, arc, readout

    func drawNeedle(value: Double, color: RGBAColor, in cg: CGContext, geometry: Geometry, scale: Double = 1) {
        let r = geometry.radius
        let needle = params.needle
        let a = angle(for: value)
        let tip = geometry.point(angle: a, radius: r * needle.length * scale)
        let tail = geometry.point(angle: a + .pi, radius: r * needle.tailLength)
        let halfWidth = r * needle.width * scale / 2
        let leftOffset = CGPoint(x: cos(a + .pi / 2) * halfWidth, y: sin(a + .pi / 2) * halfWidth)
        cg.setFillColor(color.cgColor)
        if needle.tapered {
            cg.move(to: tip)
            cg.addLine(to: CGPoint(x: tail.x + leftOffset.x, y: tail.y + leftOffset.y))
            cg.addLine(to: CGPoint(x: tail.x - leftOffset.x, y: tail.y - leftOffset.y))
        } else {
            cg.move(to: CGPoint(x: tip.x + leftOffset.x, y: tip.y + leftOffset.y))
            cg.addLine(to: CGPoint(x: tail.x + leftOffset.x, y: tail.y + leftOffset.y))
            cg.addLine(to: CGPoint(x: tail.x - leftOffset.x, y: tail.y - leftOffset.y))
            cg.addLine(to: CGPoint(x: tip.x - leftOffset.x, y: tip.y - leftOffset.y))
        }
        cg.closePath()
        cg.fillPath()
    }

    func drawHub(in cg: CGContext, geometry: Geometry) {
        let hub = geometry.radius * params.needle.hubRadius
        guard hub > 0 else { return }
        cg.setFillColor(params.textColor.cgColor)
        cg.fillEllipse(
            in: CGRect(x: geometry.center.x - hub, y: geometry.center.y - hub, width: 2 * hub, height: 2 * hub))
    }

    func drawArc(value: Double, color: RGBAColor, in cg: CGContext, geometry: Geometry) {
        guard value > params.minValue else { return }
        let r = geometry.radius
        cg.setLineWidth(r * params.arcWidth)
        cg.setLineCap(.butt)
        strokeArc(params.minValue...value, radius: r * arcRadius, color: color, in: cg, geometry: geometry)
    }

    func drawReadout(value: Double?, in cg: CGContext, geometry: Geometry) {
        let text = value.map { ValueFormatting.format($0, decimals: params.decimals) } ?? "--"
        // The readout sits in the bottom gap of the sweep, below the end-of-scale labels.
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
                style: unitStyle, in: cg)
        }
    }
}

extension RGBAColor {
    /// Linear blend of two colours.
    public static func lerp(_ a: RGBAColor, _ b: RGBAColor, _ t: Double) -> RGBAColor {
        let f = min(max(t, 0), 1)
        return RGBAColor(
            red: a.red + (b.red - a.red) * f, green: a.green + (b.green - a.green) * f,
            blue: a.blue + (b.blue - a.blue) * f, alpha: a.alpha + (b.alpha - a.alpha) * f)
    }
}
