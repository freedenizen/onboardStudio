import CoreGraphics
import CoreText
import Foundation
import ProjectModel
import TelemetryKit

/// A filled/stroked rectangle, rounded rectangle or ellipse.
public struct ShapeRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: ShapeParams

    public init(context: ObjectContext, params: ShapeParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 0, rect.height > 0 else { return }
        cg.setAlpha(context.opacity)
        let path: CGPath =
            switch params.shape {
            case .rectangle: CGPath(rect: rect, transform: nil)
            case .roundedRectangle:
                CGPath(
                    roundedRect: rect, cornerWidth: min(rect.width, rect.height) * params.cornerRadius,
                    cornerHeight: min(rect.width, rect.height) * params.cornerRadius, transform: nil)
            case .ellipse: CGPath(ellipseIn: rect, transform: nil)
            }
        if let end = params.gradientEndColor,
            let gradient = CGGradient(
                colorsSpace: PixelBuffers.colorSpace, colors: [params.fillColor.cgColor, end.cgColor] as CFArray,
                locations: [0, 1])
        {
            cg.saveGState()
            cg.addPath(path)
            cg.clip()
            let horizontal = params.gradientHorizontal
            cg.drawLinearGradient(
                gradient, start: CGPoint(x: rect.minX, y: rect.minY),
                end: horizontal ? CGPoint(x: rect.maxX, y: rect.minY) : CGPoint(x: rect.minX, y: rect.maxY),
                options: [])
            cg.restoreGState()
        } else if params.fillColor.alpha > 0 {
            cg.setFillColor(params.fillColor.cgColor)
            cg.addPath(path)
            cg.fillPath()
        }
        if params.strokeWidth > 0, params.strokeColor.alpha > 0 {
            cg.setStrokeColor(params.strokeColor.cgColor)
            cg.setLineWidth(params.strokeWidth * size.height)
            cg.addPath(path)
            cg.strokePath()
        }
    }
}

/// Static caption text, optionally outlined, on an optional background.
public struct TextRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: TextParams

    public init(context: ObjectContext, params: TextParams) {
        self.context = context
        self.params = params
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard rect.width > 0, rect.height > 0, !params.text.isEmpty else { return }
        cg.setAlpha(context.opacity)
        if params.backgroundColor.alpha > 0 {
            cg.fillRoundedRect(rect, radius: rect.height * 0.15, color: params.backgroundColor.cgColor)
        }
        let style = TextDrawing.Style(
            fontName: params.fontName, pointSize: rect.height * params.fontScale, color: params.color,
            weightBold: params.bold)
        let textSize = TextDrawing.size(of: params.text, style: style)
        let padding = rect.height * 0.1
        let y = rect.midY - textSize.height / 2
        let anchor: (CGPoint, TextDrawing.HorizontalAlignment) =
            switch params.alignment {
            case .leading: (CGPoint(x: rect.minX + padding, y: y), .leading)
            case .center: (CGPoint(x: rect.midX, y: y), .center)
            case .trailing: (CGPoint(x: rect.maxX - padding, y: y), .trailing)
            }
        if params.outlineWidth > 0 {
            var outline = style
            outline.color = params.outlineColor
            let w = style.pointSize * params.outlineWidth
            for (dx, dy) in [(-w, 0), (w, 0), (0, -w), (0, w), (-w, -w), (w, w), (-w, w), (w, -w)] {
                TextDrawing.draw(
                    params.text, at: CGPoint(x: anchor.0.x + dx, y: anchor.0.y + dy), alignment: anchor.1,
                    style: outline, in: cg)
            }
        }
        TextDrawing.draw(params.text, at: anchor.0, alignment: anchor.1, style: style, in: cg)
    }
}

/// An embedded image, aspect-fitted into its frame, with optional data-driven rotation, opacity
/// and flashing.
public struct ImageRenderer: OverlayDrawing {
    public let context: ObjectContext
    public let params: ImageObjectParams
    public let image: LoadedImage?

    public init(context: ObjectContext, params: ImageObjectParams, image: LoadedImage?) {
        self.context = context
        self.params = params
        self.image = image
    }

    public func draw(in cg: CGContext, size: CGSize, time: Double) {
        let rect = context.rect(in: size)
        guard let image, rect.width > 0, rect.height > 0 else { return }
        let sample = context.sample(at: time)
        var alpha = context.opacity
        if let channel = params.opacityChannel, let role = ChannelValue.role(channel), let value = sample?[role] {
            alpha *= min(max(value * params.opacityScale, 0), 1)
        }
        if let channel = params.flashChannel, let role = ChannelValue.role(channel), let value = sample?[role],
            value > params.flashThreshold
        {
            let phase = (time * params.flashHertz).truncatingRemainder(dividingBy: 1)
            if phase >= 0.5 { return }
        }
        guard alpha > 0 else { return }
        var degrees = params.rotation
        if let channel = params.rotationChannel, let role = ChannelValue.role(channel), let value = sample?[role] {
            degrees += value * params.degreesPerUnit
        }
        // Fit the image into the frame.
        let imageSize = CGSize(width: image.width, height: image.height)
        var drawRect = rect
        if params.keepAspect {
            let scale = min(rect.width / imageSize.width, rect.height / imageSize.height)
            let w = imageSize.width * scale
            let h = imageSize.height * scale
            drawRect = CGRect(x: rect.midX - w / 2, y: rect.midY - h / 2, width: w, height: h)
        }
        cg.saveGState()
        cg.setAlpha(alpha)
        cg.translateBy(x: rect.midX, y: rect.midY)
        cg.rotate(by: degrees * .pi / 180)
        cg.translateBy(x: -rect.midX, y: -rect.midY)
        // CG draws images bottom-up; flip locally so the picture is upright in our top-left space.
        cg.translateBy(x: 0, y: drawRect.maxY + drawRect.minY)
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .high
        cg.draw(image.image, in: drawRect)
        cg.restoreGState()
    }
}
