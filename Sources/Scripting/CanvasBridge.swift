import CoreGraphics
import Foundation
import JavaScriptCore
import ProjectModel
import RenderKit

/// The drawing API a script sees as `canvas`. Coordinates are pixels inside the object's frame,
/// origin top-left. Every method is a thin wrapper over Core Graphics on the current frame.
@objc protocol CanvasExports: JSExport {
    var width: Double { get }
    var height: Double { get }
    var time: Double { get }
    func fill(_ color: String)
    func stroke(_ color: String, _ width: Double)
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double)
    func strokeRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double)
    func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double)
    func strokeRoundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double)
    func circle(_ cx: Double, _ cy: Double, _ r: Double)
    func strokeCircle(_ cx: Double, _ cy: Double, _ r: Double)
    func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double)
    func polygon(_ points: [Double])
    func strokePolygon(_ points: [Double])
    func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startDegrees: Double, _ endDegrees: Double)
    func text(_ text: String, _ x: Double, _ y: Double, _ options: [String: Any]?)
    func textWidth(_ text: String, _ options: [String: Any]?) -> Double
    // swiftlint:disable:next function_parameter_count
    func gradientRect(
        _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ from: String, _ to: String, _ vertical: Bool)
    func opacity(_ alpha: Double)
}

/// Draws script calls into the current CGContext. One instance per renderer; the context is
/// swapped in for each `background` / `frame` call.
final class CanvasBridge: NSObject, CanvasExports {
    var context: CGContext?
    var width: Double = 0
    var height: Double = 0
    var time: Double = 0
    private var fillColor = RGBAColor.white
    private var strokeColor = RGBAColor.white
    private var lineWidth = 2.0

    /// Number of drawing calls since the last reset (a cheap per-frame work measure).
    private(set) var calls = 0

    func begin(context: CGContext, width: Double, height: Double, time: Double) {
        self.context = context
        self.width = width
        self.height = height
        self.time = time
        fillColor = .white
        strokeColor = .white
        lineWidth = 2
        calls = 0
    }

    func end() { context = nil }

    // MARK: - State

    func fill(_ color: String) { fillColor = RGBAColor(css: color) ?? fillColor }

    func stroke(_ color: String, _ width: Double) {
        strokeColor = RGBAColor(css: color) ?? strokeColor
        lineWidth = max(0, width)
    }

    func opacity(_ alpha: Double) { context?.setAlpha(min(max(alpha, 0), 1)) }

    // MARK: - Shapes

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        guard let cg = context else { return }
        calls += 1
        cg.setFillColor(fillColor.cgColor)
        cg.fill(CGRect(x: x, y: y, width: w, height: h))
    }

    func strokeRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) {
        guard let cg = context else { return }
        calls += 1
        cg.setStrokeColor(strokeColor.cgColor)
        cg.setLineWidth(lineWidth)
        cg.stroke(CGRect(x: x, y: y, width: w, height: h))
    }

    func roundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double) {
        guard let cg = context else { return }
        calls += 1
        let r = min(max(radius, 0), min(w, h) / 2)
        cg.setFillColor(fillColor.cgColor)
        cg.addPath(
            CGPath(
                roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        cg.fillPath()
    }

    func strokeRoundRect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ radius: Double) {
        guard let cg = context else { return }
        calls += 1
        let r = min(max(radius, 0), min(w, h) / 2)
        cg.setStrokeColor(strokeColor.cgColor)
        cg.setLineWidth(lineWidth)
        cg.addPath(
            CGPath(
                roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerWidth: r, cornerHeight: r, transform: nil))
        cg.strokePath()
    }

    func circle(_ cx: Double, _ cy: Double, _ r: Double) {
        guard let cg = context else { return }
        calls += 1
        cg.setFillColor(fillColor.cgColor)
        cg.fillEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }

    func strokeCircle(_ cx: Double, _ cy: Double, _ r: Double) {
        guard let cg = context else { return }
        calls += 1
        cg.setStrokeColor(strokeColor.cgColor)
        cg.setLineWidth(lineWidth)
        cg.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }

    func line(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        guard let cg = context else { return }
        calls += 1
        cg.setStrokeColor(strokeColor.cgColor)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.round)
        cg.move(to: CGPoint(x: x1, y: y1))
        cg.addLine(to: CGPoint(x: x2, y: y2))
        cg.strokePath()
    }

    private func addPolygon(_ points: [Double], to cg: CGContext) -> Bool {
        guard points.count >= 6 else { return false }
        cg.move(to: CGPoint(x: points[0], y: points[1]))
        for index in stride(from: 2, to: points.count - 1, by: 2) {
            cg.addLine(to: CGPoint(x: points[index], y: points[index + 1]))
        }
        cg.closePath()
        return true
    }

    func polygon(_ points: [Double]) {
        guard let cg = context, addPolygon(points, to: cg) else { return }
        calls += 1
        cg.setFillColor(fillColor.cgColor)
        cg.fillPath()
    }

    func strokePolygon(_ points: [Double]) {
        guard let cg = context, addPolygon(points, to: cg) else { return }
        calls += 1
        cg.setStrokeColor(strokeColor.cgColor)
        cg.setLineWidth(lineWidth)
        cg.setLineJoin(.round)
        cg.strokePath()
    }

    /// Strokes an arc; angles in degrees, 0 = right, clockwise on screen.
    func arc(_ cx: Double, _ cy: Double, _ r: Double, _ startDegrees: Double, _ endDegrees: Double) {
        guard let cg = context else { return }
        calls += 1
        cg.setStrokeColor(strokeColor.cgColor)
        cg.setLineWidth(lineWidth)
        cg.setLineCap(.butt)
        cg.addArc(
            center: CGPoint(x: cx, y: cy), radius: r, startAngle: startDegrees * .pi / 180,
            endAngle: endDegrees * .pi / 180, clockwise: false)
        cg.strokePath()
    }

    // swiftlint:disable:next function_parameter_count
    func gradientRect(
        _ x: Double, _ y: Double, _ w: Double, _ h: Double, _ from: String, _ to: String, _ vertical: Bool
    ) {
        guard let cg = context, let a = RGBAColor(css: from), let b = RGBAColor(css: to),
            let gradient = CGGradient(
                colorsSpace: PixelBuffers.colorSpace, colors: [a.cgColor, b.cgColor] as CFArray, locations: [0, 1])
        else { return }
        calls += 1
        cg.saveGState()
        cg.clip(to: CGRect(x: x, y: y, width: w, height: h))
        let start = CGPoint(x: x, y: y)
        let end = vertical ? CGPoint(x: x, y: y + h) : CGPoint(x: x + w, y: y)
        cg.drawLinearGradient(gradient, start: start, end: end, options: [])
        cg.restoreGState()
    }

    // MARK: - Text

    private func style(from options: [String: Any]?) -> (TextDrawing.Style, TextDrawing.HorizontalAlignment) {
        let size = (options?["size"] as? Double) ?? max(12, height * 0.3)
        let bold = (options?["bold"] as? Bool) ?? false
        let mono = (options?["mono"] as? Bool) ?? false
        let color = (options?["color"] as? String).flatMap { RGBAColor(css: $0) } ?? fillColor
        let font = (options?["font"] as? String) ?? (mono ? "Menlo" : "Helvetica Neue")
        let alignment: TextDrawing.HorizontalAlignment =
            switch (options?["align"] as? String) ?? "left" {
            case "center": .center
            case "right": .trailing
            default: .leading
            }
        return (TextDrawing.Style(fontName: font, pointSize: size, color: color, weightBold: bold), alignment)
    }

    /// Draws `text` with its baseline box anchored at (x, y): y is the top of the text.
    func text(_ text: String, _ x: Double, _ y: Double, _ options: [String: Any]?) {
        guard let cg = context else { return }
        calls += 1
        let (style, alignment) = style(from: options)
        let anchorY: Double
        if (options?["baseline"] as? String) == "middle" {
            anchorY = y - TextDrawing.size(of: text, style: style).height / 2
        } else {
            anchorY = y
        }
        TextDrawing.draw(text, at: CGPoint(x: x, y: anchorY), alignment: alignment, style: style, in: cg)
    }

    func textWidth(_ text: String, _ options: [String: Any]?) -> Double {
        TextDrawing.size(of: text, style: style(from: options).0).width
    }
}

extension RGBAColor {
    /// `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb(r,g,b)`, `rgba(r,g,b,a)` or a few named colours.
    public init?(css: String) {
        let text = css.trimmingCharacters(in: .whitespaces).lowercased()
        if text.hasPrefix("#") {
            self.init(hex: text)
            return
        }
        if text.hasPrefix("rgb") {
            let inner = text.drop { $0 != "(" }.dropFirst().prefix { $0 != ")" }
            let parts = inner.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 3 else { return nil }
            self.init(
                red: parts[0] / 255, green: parts[1] / 255, blue: parts[2] / 255, alpha: parts.count > 3 ? parts[3] : 1)
            return
        }
        switch text {
        case "white": self = .white
        case "black": self = .black
        case "red": self = .red
        case "orange", "accent": self = .accent
        case "green": self.init(red: 0.25, green: 0.85, blue: 0.35)
        case "yellow": self.init(red: 1, green: 0.85, blue: 0.1)
        case "blue": self.init(red: 0.2, green: 0.5, blue: 1)
        case "transparent", "none": self.init(red: 0, green: 0, blue: 0, alpha: 0)
        default: return nil
        }
    }
}
