import CoreGraphics
import CoreText
import Foundation

/// Burns the project time into a corner of the frame. Used by `overlaygen render` before real
/// display objects exist, and handy for verifying preview/export sync.
public struct TimestampOverlay: OverlayDrawing {
    public var fontSize: Double
    public var label: String?

    public init(fontSize: Double = 0.05, label: String? = nil) {
        self.fontSize = fontSize
        self.label = label
    }

    public func draw(in context: CGContext, size: CGSize, time: Double) {
        let text = (label.map { "\($0)  " } ?? "") + Self.format(time)
        let pointSize = max(12, size.height * fontSize)
        let font = CTFontCreateWithName("Menlo-Bold" as CFString, pointSize, nil)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: PixelBuffers.color(red: 1, green: 1, blue: 1),
        ]
        guard let attributed = CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary) else {
            return
        }
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        let padding = pointSize * 0.4
        // Top-left corner; the context's origin is top-left with y growing downward.
        let origin = CGPoint(x: padding, y: padding)

        context.saveGState()
        context.setFillColor(PixelBuffers.color(red: 0, green: 0, blue: 0, alpha: 0.6))
        context.fill(
            CGRect(
                x: origin.x - padding / 2, y: origin.y - padding / 2, width: bounds.width + padding,
                height: bounds.height + padding))
        // CoreText draws with a bottom-left origin; flip locally.
        context.translateBy(x: origin.x, y: origin.y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: 0, y: -bounds.minY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// `m:ss.hh`, or `h:mm:ss.hh` from one hour.
    public static func format(_ seconds: Double) -> String {
        let total = max(0, seconds)
        let hours = Int(total / 3600)
        let minutes = Int(total.truncatingRemainder(dividingBy: 3600) / 60)
        let secs = total.truncatingRemainder(dividingBy: 60)
        return hours > 0
            ? String(format: "%d:%02d:%05.2f", hours, minutes, secs) : String(format: "%d:%05.2f", minutes, secs)
    }
}
