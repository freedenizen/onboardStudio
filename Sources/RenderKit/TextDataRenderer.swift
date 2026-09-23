import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A labelled numeric readout of one channel, e.g. `SPEED  123 mph`, with number formatting.
public struct TextDataRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: TextDataParams

    public init(context: ObjectContext, params: TextDataParams) {
        self.context = context
        self.params = params
    }

    /// The formatted value text (without caption or unit) for a raw channel value.
    func valueText(for raw: Double?) -> String {
        guard var value = raw else { return params.prefix + "--" }
        if params.absoluteValue { value = abs(value) }
        value = value * params.multiplier + params.offset
        return params.prefix
            + ValueFormatting.format(
                value, decimals: params.decimals, thousandsSeparator: params.thousandsSeparator,
                plusSign: params.showPlusSign, minimumIntegerDigits: params.minimumIntegerDigits)
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: rect.height * 0.15, color: params.backgroundColor.cgColor)
        }
        let raw = ChannelValue.display(params.channel, in: context.sample(at: time), units: context.units)
        let unit = context.units.label(for: params.channel) ?? params.unitLabel
        let text = valueText(for: raw)
        let padding = rect.height * 0.12
        let labelStyle = context.styled(
            TextDrawing.Style(pointSize: rect.height * params.labelScale, color: params.textColor))
        // Warning zones recolour the number (water/oil temperature style) without a script.
        let shown = raw.map { $0 * params.multiplier + params.offset }
        let valueColor = shown.flatMap { params.zones.zone(containing: $0)?.color } ?? params.textColor
        let valueStyle =
            params.fontName.isEmpty
            ? context.styled(TextDrawing.Style.mono(rect.height * params.fontScale, color: valueColor))
            : context.styled(
                TextDrawing.Style(
                    fontName: params.fontName, pointSize: rect.height * params.fontScale, color: valueColor))
        let unitStyle = context.styled(
            TextDrawing.Style(
                pointSize: rect.height * params.fontScale * 0.5, color: params.textColor, weightBold: false))

        let valueSize = TextDrawing.size(of: text, style: valueStyle)
        let unitSize = unit.isEmpty ? .zero : TextDrawing.size(of: unit, style: unitStyle)
        let gap = unit.isEmpty ? 0 : rect.height * 0.08
        let groupWidth = valueSize.width + gap + unitSize.width
        let valueX: Double =
            switch params.alignment {
            case .leading:
                rect.minX + padding
                    + (params.label.isEmpty ? 0 : TextDrawing.size(of: params.label, style: labelStyle).width + padding)
            case .center: rect.midX - groupWidth / 2
            case .trailing: rect.maxX - padding - groupWidth
            }
        if !params.label.isEmpty {
            TextDrawing.draw(
                params.label, at: CGPoint(x: rect.minX + padding, y: rect.minY + padding), style: labelStyle, in: cg)
        }
        let valueY = rect.midY - valueSize.height / 2
        TextDrawing.draw(text, at: CGPoint(x: valueX, y: valueY), style: valueStyle, in: cg)
        if !unit.isEmpty {
            TextDrawing.draw(
                unit,
                at: CGPoint(
                    x: valueX + valueSize.width + gap,
                    y: valueY + valueSize.height - unitSize.height - rect.height * 0.04), style: unitStyle, in: cg)
        }
    }
}
