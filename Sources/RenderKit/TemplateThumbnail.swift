import CoreGraphics
import Foundation
import ProjectModel

/// A picture of what a template lays out (#44), for the welcome window's cards and the Save as
/// Template sheet: its camera areas as a dim stand-in for footage, and its overlays drawn as they
/// are before any data is loaded — which is how they look in a new project from it.
public enum TemplateThumbnail {
    public static func image(of template: ProjectTemplate, width: Int = 320) -> CGImage? {
        let settings = template.settings
        let aspect = Double(max(1, settings.outputHeight)) / Double(max(1, settings.outputWidth))
        let height = max(1, Int((Double(width) * aspect).rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: PixelBuffers.colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        let size = CGSize(width: width, height: height)
        context.translateBy(x: 0, y: size.height)
        context.scaleBy(x: 1, y: -1)

        let project = Project(settings: settings, displayObjects: template.displayObjects, timeline: template.timeline)
        let objects = project.displayObjects(at: 0)
        drawBackdrop(in: context, size: size)
        for object in objects where object.isVisible {
            guard case .video = object.kind else { continue }
            drawCameraArea(object.frame.scaled(toWidth: size.width, height: size.height), in: context)
        }
        context.saveGState()
        context.setAlpha(settings.overlayOpacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for overlay in RenderPlanner.overlays(for: project, objects: objects, sessions: [:]) {
            context.saveGState()
            overlay.draw(in: context, size: size, time: 0)
            context.restoreGState()
        }
        context.endTransparencyLayer()
        context.restoreGState()
        return context.makeImage()
    }

    /// Dusk over tarmac: dark enough that white overlays read, not so dark it looks like an error.
    static func drawBackdrop(in context: CGContext, size: CGSize) {
        let colors = [
            PixelBuffers.color(red: 0.24, green: 0.28, blue: 0.34),
            PixelBuffers.color(red: 0.10, green: 0.10, blue: 0.11),
        ]
        guard let gradient = CGGradient(colorsSpace: PixelBuffers.colorSpace, colors: colors as CFArray, locations: nil)
        else { return }
        context.drawLinearGradient(
            gradient, start: .zero, end: CGPoint(x: 0, y: size.height), options: [.drawsAfterEndLocation])
    }

    /// A second camera's picture-in-picture, outlined so the layout reads without footage.
    static func drawCameraArea(_ rect: CGRect, in context: CGContext) {
        // The main camera fills the frame and is what the backdrop already stands for.
        guard rect.width < CGFloat(context.width) * 0.98 || rect.height < CGFloat(context.height) * 0.98 else { return }
        context.setFillColor(PixelBuffers.color(red: 0.32, green: 0.36, blue: 0.42))
        context.fill(rect)
        context.setStrokeColor(PixelBuffers.color(red: 0.6, green: 0.64, blue: 0.7))
        context.setLineWidth(1)
        context.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
    }
}
