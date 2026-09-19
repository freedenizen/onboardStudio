import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit

/// A translucent wheel rim whose top-centre marker follows the steering angle.
public struct SteeringWheelRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: SteeringWheelParams

    public init(context: ObjectContext, params: SteeringWheelParams) {
        self.context = context
        self.params = params
    }

    /// Degrees clockwise at `time` (0 without data).
    func rotation(at time: Double) -> Double {
        guard let role = ChannelValue.role(params.channel), let value = context.sample(at: time)?[role] else {
            return 0
        }
        return params.rotation(for: value)
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        let diameter = min(rect.width, rect.height)
        guard diameter > 8 else { return }
        cg.saveGState()
        defer { cg.restoreGState() }
        cg.setAlpha(context.opacity)
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let outer = diameter / 2
        let rim = max(2, outer * min(max(params.rimWidth, 0.02), 0.6))
        let radius = outer - rim / 2
        let angle = rotation(at: time) * .pi / 180

        if params.showSpokes, params.spokeColor.alpha > 0 {
            cg.saveGState()
            cg.translateBy(x: centre.x, y: centre.y)
            cg.rotate(by: angle)
            cg.setStrokeColor(params.spokeColor.cgColor)
            cg.setLineWidth(rim * 0.8)
            cg.setLineCap(.butt)
            for spoke in [Double.pi, 0, Double.pi / 2] {  // left, right, down
                cg.move(to: CGPoint(x: cos(spoke) * outer * 0.22, y: sin(spoke) * outer * 0.22))
                cg.addLine(to: CGPoint(x: cos(spoke) * (radius - rim / 2), y: sin(spoke) * (radius - rim / 2)))
            }
            cg.strokePath()
            cg.setFillColor(params.spokeColor.cgColor)
            cg.fillEllipse(in: CGRect(x: -outer * 0.22, y: -outer * 0.22, width: outer * 0.44, height: outer * 0.44))
            cg.restoreGState()
        }

        if params.rimColor.alpha > 0 {
            cg.setStrokeColor(params.rimColor.cgColor)
            cg.setLineWidth(rim)
            cg.strokeEllipse(
                in: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
        }

        if params.edgeColor.alpha > 0 {
            cg.setStrokeColor(params.edgeColor.cgColor)
            cg.setLineWidth(max(1, outer * 0.008))
            for edge in [radius - rim / 2, radius + rim / 2] {
                cg.strokeEllipse(in: CGRect(x: centre.x - edge, y: centre.y - edge, width: edge * 2, height: edge * 2))
            }
        }

        // The marker sits at twelve o'clock when the wheel is straight and turns clockwise for a
        // right turn; y grows downwards in the overlay context, so a positive rotation is clockwise.
        if params.markerColor.alpha > 0 {
            let direction = angle - .pi / 2
            let inner = radius - rim / 2
            let outerEdge = radius + rim / 2
            cg.setStrokeColor(params.markerColor.cgColor)
            cg.setLineWidth(max(2, outer * params.markerWidth))
            cg.setLineCap(.butt)
            cg.move(to: CGPoint(x: centre.x + cos(direction) * inner, y: centre.y + sin(direction) * inner))
            cg.addLine(to: CGPoint(x: centre.x + cos(direction) * outerEdge, y: centre.y + sin(direction) * outerEdge))
            cg.strokePath()
        }
    }
}
