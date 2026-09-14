import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// Friction-circle plot: lateral G on the x axis, longitudinal G on the y axis (acceleration up).
public struct GForceRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: GForceParams

    public init(context: ObjectContext, params: GForceParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 4, rect.height > 4 else { return }
        cg.setAlpha(context.opacity)
        let radius = min(rect.width, rect.height) / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)

        let key = context.cacheKey("gforce|\(params.hashValue)", size: size)
        if let face = context.cache.image(
            for: key, size: rect.size,
            draw: { faceContext, faceSize in
                drawFace(
                    in: faceContext, center: CGPoint(x: faceSize.width / 2, y: faceSize.height / 2),
                    radius: min(faceSize.width, faceSize.height) / 2)
            })
        {
            context.cache.drawImage(face, in: rect, context: cg)
        }

        let plotRadius = radius * 0.86
        let scale = plotRadius / max(params.maxG, 0.1)
        func point(lateral: Double, longitudinal: Double) -> CGPoint {
            let clampedLat = min(max(lateral, -params.maxG), params.maxG)
            let clampedLong = min(max(longitudinal, -params.maxG), params.maxG)
            return CGPoint(x: center.x + clampedLat * scale, y: center.y - clampedLong * scale)
        }

        if params.trailSeconds > 0, let sampler = context.sampler {
            let steps = 12
            for step in stride(from: steps, through: 1, by: -1) {
                let t = time - params.trailSeconds * Double(step) / Double(steps)
                let sample = sampler.sample(at: context.inputTime(t))
                guard let lat = sample[.lateralG], let long = sample[.longitudinalG] else { continue }
                let p = point(lateral: lat, longitudinal: long)
                let alpha = 0.5 * (1 - Double(step) / Double(steps + 1))
                var color = params.dotColor
                color.alpha *= alpha
                cg.setFillColor(color.cgColor)
                let r = radius * 0.035
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
            }
        }

        let sample = context.sample(at: time)
        let lateral = sample?[.lateralG] ?? 0
        let longitudinal = sample?[.longitudinalG] ?? 0
        let p = point(lateral: lateral, longitudinal: longitudinal)
        let r = radius * 0.07
        cg.setFillColor(params.dotColor.cgColor)
        cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))

        if params.showValues {
            let style = TextDrawing.Style.mono(radius * 0.13)
            TextDrawing.draw(
                String(format: "%.2f", lateral),
                at: CGPoint(x: rect.minX + radius * 0.06, y: rect.minY + radius * 0.04), style: style, in: cg)
            TextDrawing.draw(
                String(format: "%.2f", longitudinal),
                at: CGPoint(x: rect.maxX - radius * 0.06, y: rect.minY + radius * 0.04), alignment: .trailing,
                style: style, in: cg)
        }
    }

    func drawFace(in cg: CGContext, center: CGPoint, radius: Double) {
        cg.setFillColor(params.faceColor.cgColor)
        cg.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        let plotRadius = radius * 0.86
        cg.setStrokeColor(params.gridColor.cgColor)
        cg.setLineWidth(max(1, radius * 0.012))
        var g = params.ringStep
        while g <= params.maxG + 1e-9 {
            let r = plotRadius * g / params.maxG
            cg.strokeEllipse(in: CGRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
            let style = TextDrawing.Style(pointSize: radius * 0.09, color: params.gridColor, weightBold: false)
            TextDrawing.draw(
                String(format: "%g", g), at: CGPoint(x: center.x + radius * 0.02, y: center.y - r), style: style, in: cg
            )
            g += params.ringStep
        }
        cg.move(to: CGPoint(x: center.x - plotRadius, y: center.y))
        cg.addLine(to: CGPoint(x: center.x + plotRadius, y: center.y))
        cg.move(to: CGPoint(x: center.x, y: center.y - plotRadius))
        cg.addLine(to: CGPoint(x: center.x, y: center.y + plotRadius))
        cg.strokePath()
    }
}
