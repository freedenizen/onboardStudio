import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A horizontal or vertical bar filled from the minimum to the current value, optionally split
/// into segments and coloured by zones.
public struct BarRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: BarParams

    public init(context: ObjectContext, params: BarParams) {
        self.context = context
        self.params = params
    }

    struct Caption {
        var text: String
        var style: TextDrawing.Style
        var origin: CGPoint
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 2, rect.height > 2 else { return }
        cg.setAlpha(context.opacity)
        let value = ChannelValue.display(params.channel, in: context.sample(at: time), speedUnit: params.speedUnit)
        let (bar, caption) = layout(in: rect, value: value)
        let horizontal = params.orientation == .horizontal
        let thickness = horizontal ? bar.height : bar.width
        let radius = thickness * params.cornerRadius

        cg.fillRoundedRect(bar, radius: radius, color: params.trackColor.cgColor)
        if !params.zoneColorsFill { drawZoneBands(in: cg, bar: bar) }
        drawFill(in: cg, bar: bar, radius: radius, value: value)
        if let caption {
            TextDrawing.draw(caption.text, at: caption.origin, style: caption.style, in: cg)
        }
    }

    /// Caption and value share the object with the bar: on the leading edge of a horizontal bar,
    /// below a vertical one. The font shrinks so the text always fits.
    func layout(in rect: CGRect, value: Double?) -> (bar: CGRect, caption: Caption?) {
        let unit = ChannelValue.role(params.channel) == .speed ? params.speedUnit.rawValue : params.unitLabel
        var pieces: [String] = []
        if !params.label.isEmpty { pieces.append(params.label) }
        if params.showValue {
            let valueText = value.map { ValueFormatting.format($0, decimals: params.decimals) } ?? "--"
            pieces.append(unit.isEmpty ? valueText : "\(valueText) \(unit)")
        }
        let text = pieces.joined(separator: " ")
        guard !text.isEmpty else { return (rect, nil) }
        if params.orientation == .horizontal {
            var style = TextDrawing.Style(pointSize: rect.height * 0.55, color: params.textColor)
            var textSize = TextDrawing.size(of: text, style: style)
            let maxWidth = rect.width * 0.45
            if textSize.width > maxWidth {
                style.pointSize *= maxWidth / textSize.width
                textSize = TextDrawing.size(of: text, style: style)
            }
            let gap = rect.height * 0.25
            let bar = CGRect(
                x: rect.minX + textSize.width + gap, y: rect.minY, width: rect.width - textSize.width - gap,
                height: rect.height)
            return (
                bar,
                Caption(text: text, style: style, origin: CGPoint(x: rect.minX, y: rect.midY - textSize.height / 2))
            )
        }
        var style = TextDrawing.Style(pointSize: min(rect.height * 0.12, rect.width * 0.3), color: params.textColor)
        var textSize = TextDrawing.size(of: text, style: style)
        if textSize.width > rect.width {
            style.pointSize *= rect.width / textSize.width
            textSize = TextDrawing.size(of: text, style: style)
        }
        let gap = textSize.height * 0.3
        let bar = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height - textSize.height - gap)
        let origin = CGPoint(x: rect.midX - textSize.width / 2, y: rect.maxY - textSize.height)
        return (bar, Caption(text: text, style: style, origin: origin))
    }

    var span: Double { max(params.maxValue - params.minValue, 0.000_001) }

    func drawZoneBands(in cg: CGContext, bar: CGRect) {
        let horizontal = params.orientation == .horizontal
        for zone in params.zones {
            let a = min(max((zone.from - params.minValue) / span, 0), 1)
            let b = min(max(((zone.to ?? params.maxValue) - params.minValue) / span, 0), 1)
            guard b > a else { continue }
            var band = zone.color
            band.alpha *= 0.5
            cg.setFillColor(band.cgColor)
            cg.fill(subrect(of: bar, from: a, to: b, horizontal: horizontal))
        }
    }

    func drawFill(in cg: CGContext, bar: CGRect, radius: Double, value: Double?) {
        let horizontal = params.orientation == .horizontal
        let fraction = value.map { min(max(($0 - params.minValue) / span, 0), 1) } ?? 0
        var fill = params.fillColor
        if params.zoneColorsFill, let value, let zone = params.zones.zone(containing: value) {
            fill = zone.color
        }
        if params.segments > 0 {
            let thickness = horizontal ? bar.height : bar.width
            let gap = thickness * 0.15
            let count = params.segments
            let lit = Int((fraction * Double(count)).rounded(.down))
            for index in 0..<count {
                var segment = subrect(
                    of: bar, from: Double(index) / Double(count), to: Double(index + 1) / Double(count),
                    horizontal: horizontal)
                segment = horizontal ? segment.insetBy(dx: gap / 2, dy: 0) : segment.insetBy(dx: 0, dy: gap / 2)
                var color = fill
                if index >= lit { color.alpha *= 0.2 }
                cg.setFillColor(color.cgColor)
                cg.addPath(
                    CGPath(roundedRect: segment, cornerWidth: radius / 2, cornerHeight: radius / 2, transform: nil))
                cg.fillPath()
            }
        } else if fraction > 0 {
            cg.setFillColor(fill.cgColor)
            cg.saveGState()
            cg.addPath(CGPath(roundedRect: bar, cornerWidth: radius, cornerHeight: radius, transform: nil))
            cg.clip()
            cg.fill(subrect(of: bar, from: 0, to: fraction, horizontal: horizontal))
            cg.restoreGState()
        }
    }

    /// The part of `bar` between fractions `a` and `b` of its length, measured from the start
    /// (left for horizontal, bottom for vertical).
    func subrect(of bar: CGRect, from a: Double, to b: Double, horizontal: Bool) -> CGRect {
        if horizontal {
            return CGRect(x: bar.minX + bar.width * a, y: bar.minY, width: bar.width * (b - a), height: bar.height)
        }
        return CGRect(x: bar.minX, y: bar.maxY - bar.height * b, width: bar.width, height: bar.height * (b - a))
    }
}
