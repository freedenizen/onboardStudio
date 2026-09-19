import CoreImage
import CoreVideo
import Foundation
import Metal

/// Renders one output frame from source video buffers and a `RenderPlan`. Video layers are
/// placed with Core Image on the GPU; overlays are drawn with Core Graphics into a pooled BGRA
/// buffer and composited on top. Safe to call from any queue; internally serialised.
public final class FrameCompositor: @unchecked Sendable {
    public let plan: RenderPlan
    private let context: CIContext
    private let overlayPool: CVPixelBufferPool
    private let lock = NSLock()

    public init(plan: RenderPlan) throws {
        self.plan = plan
        let options: [CIContextOption: Any] = [
            .cacheIntermediates: false, .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
        ]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options.merging([.useSoftwareRenderer: true]) { $1 })
        }
        overlayPool = try PixelBuffers.makePool(width: plan.outputWidth, height: plan.outputHeight)
    }

    /// Renders the frame at `time` into `output`, which must be a BGRA buffer of the plan's size.
    public func render(sources: [Int32: CVPixelBuffer], time: Double, into output: CVPixelBuffer) throws {
        lock.lock()
        defer { lock.unlock() }
        // Core Image and CoreVideo objects are autoreleased; callers may render thousands of
        // frames without returning to a run loop.
        try autoreleasepool { try renderLocked(sources: sources, time: time, into: output) }
    }

    private func renderLocked(sources: [Int32: CVPixelBuffer], time: Double, into output: CVPixelBuffer) throws {
        let clear =
            CIColor(
                red: plan.background.red, green: plan.background.green, blue: plan.background.blue,
                alpha: plan.background.alpha, colorSpace: PixelBuffers.colorSpace) ?? .black
        var image = CIImage(color: clear).cropped(to: CGRect(origin: .zero, size: plan.outputSize))
        for layer in plan.videoLayers {
            guard let buffer = sources[layer.trackID] else { continue }
            var raw = CIImage(cvPixelBuffer: buffer)
            if layer.sourceTransform != .identity {
                raw = raw.transformed(by: layer.sourceTransform)
                raw = raw.transformed(by: CGAffineTransform(translationX: -raw.extent.minX, y: -raw.extent.minY))
            }
            let source = layer.transform.apply(to: raw)
            image = place(source, layer: layer).composited(over: image)
        }
        if !plan.overlays.isEmpty {
            let overlayBuffer = try PixelBuffers.makeBuffer(from: overlayPool)
            try PixelBuffers.draw(into: overlayBuffer) { cgContext, size in
                for overlay in plan.overlays {
                    cgContext.saveGState()
                    overlay.draw(in: cgContext, size: size, time: time)
                    cgContext.restoreGState()
                }
            }
            var overlay = CIImage(cvPixelBuffer: overlayBuffer)
            if plan.overlayOpacity < 1 {
                // Core Image applies colour matrices to unpremultiplied colour, so only alpha scales.
                overlay = overlay.applyingFilter(
                    "CIColorMatrix",
                    parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(plan.overlayOpacity))])
            }
            image = overlay.composited(over: image)
        }
        context.render(
            image, to: output, bounds: CGRect(origin: .zero, size: plan.outputSize),
            colorSpace: CGColorSpaceCreateDeviceRGB())
    }

    /// Convenience for tests and thumbnails: renders into a fresh buffer.
    public func renderFrame(sources: [Int32: CVPixelBuffer], time: Double) throws -> CVPixelBuffer {
        let output = try PixelBuffers.makeBuffer(width: plan.outputWidth, height: plan.outputHeight)
        try render(sources: sources, time: time, into: output)
        return output
    }

    /// Aspect-fits the source into the layer's frame (in output pixels, top-left origin) and applies opacity.
    private func place(_ source: CIImage, layer: VideoLayer) -> CIImage {
        let target = layer.frame.scaled(toWidth: Double(plan.outputWidth), height: Double(plan.outputHeight))
        let sourceSize = source.extent.size
        guard sourceSize.width > 0, sourceSize.height > 0, target.width > 0, target.height > 0 else { return source }
        let scale = min(target.width / sourceSize.width, target.height / sourceSize.height)
        let scaledWidth = sourceSize.width * scale
        let scaledHeight = sourceSize.height * scale
        // Core Image's origin is bottom-left; convert the top-left unit frame.
        let originX = target.minX + (target.width - scaledWidth) / 2
        let originY = Double(plan.outputHeight) - target.maxY + (target.height - scaledHeight) / 2
        var image = source.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            .transformed(
                by: CGAffineTransform(
                    translationX: originX - source.extent.minX * scale, y: originY - source.extent.minY * scale))
        if layer.opacity < 1 {
            image = image.applyingFilter(
                "CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: layer.opacity)])
        }
        return image
    }
}
