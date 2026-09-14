import CoreGraphics
import CoreText
import Foundation
import ProjectModel

extension RGBAColor {
    public var cgColor: CGColor { PixelBuffers.color(red: red, green: green, blue: blue, alpha: alpha) }
}

/// Text drawing helpers for contexts whose origin is top-left (as prepared by `PixelBuffers.draw`).
public enum TextDrawing {
    public enum HorizontalAlignment: Sendable {
        case leading
        case center
        case trailing
    }

    public struct Style: Sendable {
        public var fontName: String
        public var pointSize: Double
        public var color: RGBAColor
        public var weightBold: Bool

        public init(
            fontName: String = "Helvetica Neue", pointSize: Double, color: RGBAColor = .white, weightBold: Bool = true
        ) {
            self.fontName = fontName
            self.pointSize = pointSize
            self.color = color
            self.weightBold = weightBold
        }

        public static func mono(_ size: Double, color: RGBAColor = .white) -> Style {
            Style(fontName: "Menlo-Bold", pointSize: size, color: color)
        }
    }

    /// Measures a single line.
    public static func size(of text: String, style: Style) -> CGSize {
        let line = makeLine(text, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        return CGSize(width: bounds.width, height: bounds.height)
    }

    /// Draws one line of text with its anchor at `point` (top edge; x edge per alignment).
    public static func draw(
        _ text: String, at point: CGPoint, alignment: HorizontalAlignment = .leading, style: Style,
        in context: CGContext
    ) {
        let line = makeLine(text, style: style)
        let bounds = CTLineGetBoundsWithOptions(line, [.useOpticalBounds])
        let x: Double =
            switch alignment {
            case .leading: point.x
            case .center: point.x - bounds.width / 2
            case .trailing: point.x - bounds.width
            }
        context.saveGState()
        context.translateBy(x: x, y: point.y + bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: -bounds.minX, y: -bounds.minY)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Draws text centred on `center`.
    public static func drawCentered(_ text: String, at center: CGPoint, style: Style, in context: CGContext) {
        let size = size(of: text, style: style)
        draw(
            text, at: CGPoint(x: center.x, y: center.y - size.height / 2), alignment: .center, style: style, in: context
        )
    }

    private static func makeLine(_ text: String, style: Style) -> CTLine {
        var font = CTFontCreateWithName(style.fontName as CFString, style.pointSize, nil)
        if style.weightBold, !style.fontName.lowercased().contains("bold"),
            let bold = CTFontCreateCopyWithSymbolicTraits(font, style.pointSize, nil, .boldTrait, .boldTrait)
        {
            font = bold
        }
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font, kCTForegroundColorAttributeName: style.color.cgColor,
        ]
        let attributed =
            CFAttributedStringCreate(nil, text as CFString, attributes as CFDictionary)
            ?? NSAttributedString(string: "") as CFAttributedString
        return CTLineCreateWithAttributedString(attributed)
    }
}

extension CGContext {
    /// Fills a rounded rectangle.
    func fillRoundedRect(_ rect: CGRect, radius: Double, color: CGColor) {
        let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        setFillColor(color)
        addPath(path)
        fillPath()
    }
}

/// Formats numbers for readouts.
enum ValueFormatting {
    static func format(_ value: Double, decimals: Int) -> String {
        String(format: "%.\(max(0, decimals))f", value)
    }
}
