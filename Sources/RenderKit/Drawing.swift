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

    /// Fonts are resolved through the system font server (an XPC round trip); cache them so a
    /// frame costs no lookups and parallel renders cannot pile up on the server.
    private static let fontLock = NSLock()
    nonisolated(unsafe) private static var fontCache: [String: CTFont] = [:]

    static func font(for style: Style) -> CTFont {
        // Quantise the size so a slowly resizing object does not grow the cache without bound.
        let size = (style.pointSize * 4).rounded() / 4
        let key = "\(style.fontName)|\(size)|\(style.weightBold)"
        // The lock is held across the lookup on purpose: concurrent first-time lookups from many
        // render threads have been seen to wedge the font server connection.
        fontLock.lock()
        defer { fontLock.unlock() }
        if let cached = fontCache[key] { return cached }
        var font = CTFontCreateWithName(style.fontName as CFString, size, nil)
        if style.weightBold, !style.fontName.lowercased().contains("bold"),
            let bold = CTFontCreateCopyWithSymbolicTraits(font, size, nil, .boldTrait, .boldTrait)
        {
            font = bold
        }
        fontCache[key] = font
        return font
    }

    private static func makeLine(_ text: String, style: Style) -> CTLine {
        let font = font(for: style)
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

    /// Full formatting: fixed decimals, optional thousands separators, explicit `+`, and a
    /// zero-padded integer part. `-0` never appears.
    static func format(
        _ value: Double, decimals: Int, thousandsSeparator: Bool, plusSign: Bool, minimumIntegerDigits: Int
    ) -> String {
        let places = max(0, decimals)
        var text = String(format: "%.\(places)f", abs(value))
        let negative = value < 0 && Double(text) != 0
        var integer = text
        var fraction = ""
        if let dot = text.firstIndex(of: ".") {
            integer = String(text[..<dot])
            fraction = String(text[dot...])
        }
        if integer.count < minimumIntegerDigits {
            integer = String(repeating: "0", count: minimumIntegerDigits - integer.count) + integer
        }
        if thousandsSeparator, integer.count > 3 {
            var grouped = ""
            for (offset, character) in integer.reversed().enumerated() {
                if offset > 0, offset % 3 == 0 { grouped.append(",") }
                grouped.append(character)
            }
            integer = String(grouped.reversed())
        }
        text = integer + fraction
        if negative { return "-" + text }
        if plusSign, Double(text) != 0 { return "+" + text }
        return text
    }
}
