import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Best / previous / current lap times with small lap numbers, flanked by a speed-vs-best scale
/// (marker, current speed and the difference) and a time-vs-best scale (bar and signed delta):
/// RaceRender's "timing and deltas" strip, drawn natively.
public struct LapPanelRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: LapPanelParams

    public init(context: ObjectContext, params: LapPanelParams) {
        self.context = context
        self.params = params
    }

    struct Layout {
        let rect: CGRect
        var height: Double { rect.height }
        var big: Double { height * 0.44 }
        var mid: Double { height * 0.36 }
        var small: Double { height * 0.2 }
        var label: Double { height * 0.2 }
        var labelY: Double { rect.minY + height * 0.03 }
        var scaleY: Double { rect.minY + height * 0.24 }
        var rowY: Double { rect.minY + height * 0.38 }
        var tick: Double { max(1, height * 0.012) }
        var centerTick: Double { max(2, height * 0.022) }
        var outline: Double { max(1, height * 0.014) }
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 8, rect.height > 8 else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: rect.height * 0.1, color: params.backgroundColor.cgColor)
        }
        let layout = Layout(rect: rect)
        let sample = context.sample(at: time)
        let timing = sample?.lapTiming
        let session = context.sampler?.session
        let inputTime = context.inputTime(time)

        // Lanes: [speed 0…0.2] [best 0.22…] [previous 0.42…] [current 0.62…] [time 0.82…0.98].
        let lanes = laneOrigins()
        if params.showSpeedDelta {
            drawSpeedLane(
                in: cg, layout: layout, from: rect.minX + rect.width * 0.02, to: rect.minX + rect.width * 0.2,
                sample: sample, session: session, inputTime: inputTime)
        }
        let current = timing?.currentLap
        let previous = session.flatMap { LapComparison.referenceLap(at: inputTime, session: $0, reference: .previous) }
        if params.showBest, let x = lanes["best"] {
            drawLap(
                label: params.bestLabel, number: timing?.bestLapNumber, seconds: timing?.bestLapTime,
                at: rect.minX + rect.width * x,
                layout: layout, in: cg)
        }
        if params.showPrevious, let x = lanes["previous"] {
            drawLap(
                label: params.previousLabel, number: previous?.number, seconds: previous?.duration,
                at: rect.minX + rect.width * x,
                layout: layout, in: cg)
        }
        if params.showCurrent, let x = lanes["current"] {
            drawLap(
                label: params.currentLabel, number: current?.number, seconds: timing?.elapsedInLap,
                at: rect.minX + rect.width * x,
                layout: layout, in: cg)
        }
        if params.showTimeDelta {
            let delta = session.flatMap { LapComparison.delta(at: inputTime, session: $0, reference: reference) }
            drawTimeLane(
                in: cg, layout: layout, from: rect.minX + rect.width * 0.82, to: rect.minX + rect.width * 0.98,
                delta: delta)
        }
    }

    var reference: LapComparison.Reference { params.reference.comparison }

    /// Where each lap block starts (fraction of the width), packing the enabled ones.
    func laneOrigins() -> [String: Double] {
        let blocks = [("best", params.showBest), ("previous", params.showPrevious), ("current", params.showCurrent)]
            .filter(\.1).map(\.0)
        let left = params.showSpeedDelta ? 0.22 : 0.02
        let right = params.showTimeDelta ? 0.8 : 0.98
        let step = blocks.isEmpty ? 0 : (right - left) / Double(blocks.count)
        var result: [String: Double] = [:]
        for (index, name) in blocks.enumerated() { result[name] = left + step * Double(index) }
        return result
    }

    // MARK: - Pieces

    // swiftlint:disable:next function_parameter_count
    private func text(
        _ string: String, at point: CGPoint, alignment: TextDrawing.HorizontalAlignment, size: Double, color: RGBAColor,
        in cg: CGContext
    ) {
        let style = TextDrawing.Style(pointSize: size, color: color)
        if params.outline {
            let width = max(1, size * 0.06)
            var back = style
            back.color = .black
            for dx in [-width, 0, width] {
                for dy in [-width, 0, width] where dx != 0 || dy != 0 {
                    TextDrawing.draw(
                        string, at: CGPoint(x: point.x + dx, y: point.y + dy), alignment: alignment, style: back, in: cg
                    )
                }
            }
        }
        TextDrawing.draw(string, at: point, alignment: alignment, style: style, in: cg)
    }

    // swiftlint:disable:next function_parameter_count
    private func drawLap(label: String, number: Int?, seconds: Double?, at x: Double, layout: Layout, in cg: CGContext)
    {
        text(
            label, at: CGPoint(x: x, y: layout.labelY), alignment: .leading, size: layout.label,
            color: params.labelColor, in: cg)
        let numberText = params.showLapNumbers ? number.map(String.init) ?? "" : ""
        text(
            numberText, at: CGPoint(x: x, y: layout.rowY), alignment: .leading, size: layout.small,
            color: params.textColor, in: cg)
        let timeText =
            seconds.map { TimeParsing.lapTimeString($0, decimals: max(1, min(3, params.decimals))) } ?? "-:--.-"
        let indent = params.showLapNumbers ? layout.small * 0.9 : 0
        text(
            timeText, at: CGPoint(x: x + indent, y: layout.rowY), alignment: .leading, size: layout.big,
            color: params.textColor, in: cg)
    }

    private func drawScale(in cg: CGContext, layout: Layout, from a: Double, to b: Double) {
        let y = layout.scaleY
        let step = (b - a) / 10
        let h1 = layout.height * 0.08
        let h2 = layout.height * 0.15
        for pass in 0..<2 {
            let border = pass == 0
            guard !border || params.outline else { continue }
            let color: RGBAColor = border ? .black : params.labelColor
            let extra = border ? 2 * layout.outline : 0
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(layout.tick + extra)
            cg.move(to: CGPoint(x: a, y: y))
            cg.addLine(to: CGPoint(x: b, y: y))
            cg.strokePath()
            for index in 0...10 {
                let centre = index == 5
                cg.setStrokeColor((border ? RGBAColor.black : centre ? params.textColor : params.labelColor).cgColor)
                cg.setLineWidth((centre ? layout.centerTick : layout.tick) + extra)
                let x = a + step * Double(index)
                cg.move(to: CGPoint(x: x, y: y))
                cg.addLine(to: CGPoint(x: x, y: y + (centre ? h2 : h1)))
                cg.strokePath()
            }
        }
    }

    // swiftlint:disable:next function_parameter_count
    private func drawSpeedLane(
        in cg: CGContext, layout: Layout, from a: Double, to b: Double, sample: TelemetrySample?,
        session: TelemetrySession?,
        inputTime: Double
    ) {
        drawScale(in: cg, layout: layout, from: a, to: b)
        let speed = sample?[.speed].map { context.units.value($0, of: "speed") }
        // The delta is a difference of speeds, so it converts as a speed does. That is only true
        // while every speed unit is a pure scaling of m/s; an offset unit would need the
        // difference converting rather than the endpoints, and there is no such speed unit.
        let delta = session.flatMap { LapComparison.speedDelta(at: inputTime, session: $0, reference: reference) }
            .map { context.units.value($0, of: "speed") }
        let centre = (a + b) / 2
        if let delta {
            let f = max(-1, min(1, delta / max(params.speedDeltaRange, 0.001)))
            let x = centre + f * (b - centre)
            let color = delta < 0 ? params.behindColor : params.aheadColor
            let marker = max(3, layout.height * 0.035)
            let top = layout.scaleY - 2
            let bottom = layout.scaleY + layout.height * 0.15 + 2
            if params.outline {
                cg.setStrokeColor(RGBAColor.black.cgColor)
                cg.setLineWidth(marker + 2 * layout.outline)
                cg.move(to: CGPoint(x: x, y: top))
                cg.addLine(to: CGPoint(x: x, y: bottom))
                cg.strokePath()
            }
            cg.setStrokeColor(color.cgColor)
            cg.setLineWidth(marker)
            cg.move(to: CGPoint(x: x, y: top))
            cg.addLine(to: CGPoint(x: x, y: bottom))
            cg.strokePath()
        }
        let speedText = speed.map { String(format: "%.0f", $0) } ?? "-"
        text(
            speedText, at: CGPoint(x: a + layout.mid * 1.9, y: layout.rowY), alignment: .trailing, size: layout.mid,
            color: params.textColor, in: cg)
        text(
            context.units.label(for: "speed") ?? context.speedUnit.rawValue,
            at: CGPoint(x: a + layout.mid * 2.05, y: layout.rowY + layout.mid * 0.45),
            alignment: .leading,
            size: layout.label, color: params.labelColor, in: cg)
        if let delta {
            let signed = (delta > 0 ? "+" : "") + String(format: "%.0f", delta)
            text(
                signed, at: CGPoint(x: b, y: layout.rowY), alignment: .trailing, size: layout.mid,
                color: params.textColor, in: cg)
        }
    }

    private func drawTimeLane(in cg: CGContext, layout: Layout, from a: Double, to b: Double, delta: Double?) {
        drawScale(in: cg, layout: layout, from: a, to: b)
        let centre = (a + b) / 2
        guard let delta else { return }
        let g = max(-1, min(1, delta / max(params.timeDeltaRange, 0.001)))
        let width = g * (b - centre)
        let barTop = layout.scaleY
        let barHeight = layout.height * 0.08 + 2
        let bar = CGRect(x: min(centre, centre + width), y: barTop, width: abs(width), height: barHeight)
        if params.outline {
            cg.setFillColor(RGBAColor.black.cgColor)
            cg.fill(bar.insetBy(dx: -layout.outline, dy: -layout.outline))
        }
        cg.setFillColor((delta > 0 ? params.behindColor : params.aheadColor).cgColor)
        cg.fill(bar)
        let signed = (delta > 0 ? "+" : "") + String(format: "%.2f", delta)
        text(
            signed, at: CGPoint(x: b, y: layout.rowY), alignment: .trailing, size: layout.big, color: params.textColor,
            in: cg)
    }
}

extension LapReference {
    /// The telemetry-side reference this setting names.
    var comparison: LapComparison.Reference {
        switch self {
        case .sessionBest: .sessionBest
        case .bestLap: .best
        case .previousLap: .previous
        }
    }
}
