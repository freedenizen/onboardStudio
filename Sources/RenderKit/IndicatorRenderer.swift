import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A warning light: an ISO-style glyph (ABS, traction, warning triangle, round light or plain
/// text) drawn dim until its channel condition holds, then lit with an optional glow. The lit
/// state is held for `holdSeconds` after the condition last held, by scanning the channel back
/// over that window; flashing alternates the lit glyph with the dim one.
public struct IndicatorRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: IndicatorParams

    public init(context: ObjectContext, params: IndicatorParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        var lit = isOn(at: time)
        if lit, params.flashHertz > 0 {
            lit = Int((time * params.flashHertz * 2).rounded(.down)) % 2 == 0
        }
        guard lit || params.showWhenOff else { return }
        let color = lit ? params.onColor : params.offColor
        if lit, params.glow {
            let glow = CGRect(
                x: rect.minX - rect.width * 0.1, y: rect.minY - rect.height * 0.1, width: rect.width * 1.2,
                height: rect.height * 1.2)
            var outer = params.onColor
            outer.alpha = 0.18
            cg.fillRoundedRect(glow, radius: min(glow.width, glow.height) * 0.4, color: outer.cgColor)
            var inner = params.onColor
            inner.alpha = 0.3
            cg.fillRoundedRect(rect, radius: min(rect.width, rect.height) * 0.4, color: inner.cgColor)
        }
        switch params.glyph {
        case .abs: drawABS(in: cg, rect: rect, color: color)
        case .traction: drawTraction(in: cg, rect: rect, color: color)
        case .warning: drawWarning(in: cg, rect: rect, color: color)
        case .light: drawLight(in: cg, rect: rect, color: color)
        case .text:
            drawLabel(
                params.label, in: cg, center: CGPoint(x: rect.midX, y: rect.midY), size: rect.height * 0.5, color: color
            )
        }
    }

    /// Whether the condition holds now or held within the hold window.
    func isOn(at time: Double) -> Bool {
        guard let role = ChannelValue.role(params.channel), let sampler = context.sampler else { return false }
        let inputTime = context.inputTime(time)
        func holds(_ t: Double) -> Bool {
            guard let value = sampler.session[role]?.value(at: t) else { return false }
            return params.condition.holds(value, threshold: params.threshold)
        }
        if holds(inputTime) { return true }
        guard params.holdSeconds > 0 else { return false }
        // Sample the hold window at ~20 Hz; enough for a light that stays on a fraction of a second.
        let steps = max(1, Int(params.holdSeconds * 20))
        for step in 1...steps where holds(inputTime - params.holdSeconds * Double(step) / Double(steps)) { return true }
        return false
    }

    // MARK: - Glyphs

    private func stroke(_ path: CGPath, width: Double, color: RGBAColor, in cg: CGContext) {
        if params.outline {
            cg.setStrokeColor(RGBAColor.black.cgColor)
            cg.setLineWidth(width + max(1, width * 0.6))
            cg.addPath(path)
            cg.strokePath()
        }
        cg.setStrokeColor(color.cgColor)
        cg.setLineWidth(width)
        cg.addPath(path)
        cg.strokePath()
    }

    private func drawLabel(_ text: String, in cg: CGContext, center: CGPoint, size: Double, color: RGBAColor) {
        let style = context.styled(TextDrawing.Style(pointSize: size, color: color))
        if params.outline {
            TextDrawing.drawOutlined(
                text, centeredAt: center, style: style, outline: .black, width: max(1, size * 0.08), in: cg)
        } else {
            TextDrawing.drawCentered(text, at: center, style: style, in: cg)
        }
    }

    /// Circle with "ABS" inside and a bracket either side, as on a dashboard.
    private func drawABS(in cg: CGContext, rect: CGRect, color: RGBAColor) {
        let r = min(rect.width * 0.3, rect.height * 0.36)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let t = max(2, r * 0.11)
        let circle = CGPath(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r), transform: nil)
        stroke(circle, width: t, color: color, in: cg)
        for side in [-1.0, 1.0] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: c.x + side * r * 1.2, y: c.y - r * 0.85))
            path.addQuadCurve(
                to: CGPoint(x: c.x + side * r * 1.2, y: c.y + r * 0.85),
                control: CGPoint(x: c.x + side * r * 2.0, y: c.y))
            stroke(path, width: t, color: color, in: cg)
        }
        drawLabel("ABS", in: cg, center: c, size: r * 0.62, color: color)
    }

    /// A car seen from behind over two wavy skid marks: the stability-control symbol.
    private func drawTraction(in cg: CGContext, rect: CGRect, color: RGBAColor) {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY - s * 0.08)
        let t = max(2, s * 0.06)
        let car = CGMutablePath()
        car.addRoundedRect(
            in: CGRect(x: c.x - s * 0.28, y: c.y - s * 0.2, width: s * 0.56, height: s * 0.3), cornerWidth: s * 0.1,
            cornerHeight: s * 0.1)
        car.addRoundedRect(
            in: CGRect(x: c.x - s * 0.17, y: c.y - s * 0.34, width: s * 0.34, height: s * 0.18), cornerWidth: s * 0.07,
            cornerHeight: s * 0.07)
        stroke(car, width: t, color: color, in: cg)
        // Wheels.
        cg.setFillColor(color.cgColor)
        for x in [c.x - s * 0.22, c.x + s * 0.22] {
            cg.fill(CGRect(x: x - s * 0.06, y: c.y + s * 0.08, width: s * 0.12, height: s * 0.06))
        }
        // Skid marks.
        for x in [c.x - s * 0.22, c.x + s * 0.22] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x, y: c.y + s * 0.18))
            path.addCurve(
                to: CGPoint(x: x, y: c.y + s * 0.46), control1: CGPoint(x: x - s * 0.1, y: c.y + s * 0.26),
                control2: CGPoint(x: x + s * 0.1, y: c.y + s * 0.38))
            stroke(path, width: t * 0.8, color: color, in: cg)
        }
    }

    private func drawWarning(in cg: CGContext, rect: CGRect, color: RGBAColor) {
        let s = min(rect.width, rect.height)
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: c.x, y: c.y - s * 0.42))
        path.addLine(to: CGPoint(x: c.x + s * 0.46, y: c.y + s * 0.36))
        path.addLine(to: CGPoint(x: c.x - s * 0.46, y: c.y + s * 0.36))
        path.closeSubpath()
        stroke(path, width: max(2, s * 0.07), color: color, in: cg)
        drawLabel("!", in: cg, center: CGPoint(x: c.x, y: c.y + s * 0.08), size: s * 0.42, color: color)
    }

    private func drawLight(in cg: CGContext, rect: CGRect, color: RGBAColor) {
        let s = min(rect.width, rect.height)
        let hasLabel = !params.label.isEmpty
        let r = hasLabel ? s * 0.28 : s * 0.42
        let c = CGPoint(x: rect.midX, y: hasLabel ? rect.midY - s * 0.12 : rect.midY)
        let disc = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        if params.outline {
            cg.setFillColor(RGBAColor.black.cgColor)
            cg.fillEllipse(in: disc.insetBy(dx: -max(1, r * 0.1), dy: -max(1, r * 0.1)))
        }
        cg.setFillColor(color.cgColor)
        cg.fillEllipse(in: disc)
        if hasLabel {
            drawLabel(
                params.label, in: cg, center: CGPoint(x: c.x, y: rect.midY + s * 0.3), size: s * 0.22, color: color)
        }
    }
}

extension TextDrawing {
    // Text with a dark outline: the outline colour drawn around it in eight directions.
    // swiftlint:disable:next function_parameter_count
    public static func drawOutlined(
        _ text: String, centeredAt center: CGPoint, style: Style, outline: RGBAColor, width: Double,
        in context: CGContext
    ) {
        var back = style
        back.color = outline
        for dx in [-width, 0, width] {
            for dy in [-width, 0, width] where dx != 0 || dy != 0 {
                drawCentered(text, at: CGPoint(x: center.x + dx, y: center.y + dy), style: back, in: context)
            }
        }
        drawCentered(text, at: center, style: style, in: context)
    }
}
