import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// The current gear as one large glyph with an optional caption.
public struct GearRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: GearParams

    public init(context: ObjectContext, params: GearParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: min(rect.width, rect.height) * 0.15, color: params.backgroundColor.cgColor)
        }
        let value = ChannelValue.role(params.channel).flatMap { context.sample(at: time)?[$0] }
        let text = params.text(for: value)
        let captionHeight = params.showLabel && !params.label.isEmpty ? rect.height * 0.18 : 0
        if captionHeight > 0 {
            let style = context.styled(TextDrawing.Style(pointSize: captionHeight * 0.8, color: params.textColor))
            TextDrawing.drawCentered(
                params.label, at: CGPoint(x: rect.midX, y: rect.minY + captionHeight * 0.65), style: style, in: cg)
        }
        let glyph = context.styled(TextDrawing.Style.mono(rect.height * params.fontScale, color: params.textColor))
        TextDrawing.drawCentered(
            text, at: CGPoint(x: rect.midX, y: rect.minY + captionHeight + (rect.height - captionHeight) / 2),
            style: glyph, in: cg)
    }
}

/// Lap number readout, optionally "of N".
public struct LapCounterRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: LapCounterParams

    public init(context: ObjectContext, params: LapCounterParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: rect.height * 0.15, color: params.backgroundColor.cgColor)
        }
        let sample = context.sample(at: time)
        var text = sample?.lapTiming.currentLap.map { String($0.number + params.numberOffset) } ?? "-"
        if params.showTotal, let laps = context.sampler?.session.laps, let last = laps.last {
            text += " / \(last.number + params.numberOffset)"
        }
        let padding = rect.height * 0.12
        let labelStyle = context.styled(TextDrawing.Style(pointSize: rect.height * 0.3, color: params.textColor))
        let valueStyle = context.styled(TextDrawing.Style.mono(rect.height * 0.55, color: params.textColor))
        if !params.label.isEmpty {
            TextDrawing.draw(
                params.label, at: CGPoint(x: rect.minX + padding, y: rect.minY + padding), style: labelStyle, in: cg)
        }
        let valueSize = TextDrawing.size(of: text, style: valueStyle)
        TextDrawing.draw(
            text, at: CGPoint(x: rect.maxX - padding, y: rect.midY - valueSize.height / 2), alignment: .trailing,
            style: valueStyle, in: cg)
    }
}
