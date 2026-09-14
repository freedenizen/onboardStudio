import CoreGraphics
import Foundation

/// Caches expensive static imagery (gauge faces, track outlines) keyed by a string that must
/// change whenever the drawing would (size and parameters). Thread-safe.
public final class RenderCache: @unchecked Sendable {
    private let lock = NSLock()
    private var images: [String: CGImage] = [:]

    public init() {}

    /// Returns the cached image for `key`, or builds it by drawing `size` pixels with `draw`
    /// (top-left origin, transparent background).
    public func image(for key: String, size: CGSize, draw: (CGContext, CGSize) -> Void) -> CGImage? {
        lock.lock()
        if let cached = images[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let width = max(1, Int(size.width.rounded()))
        let height = max(1, Int(size.height.rounded()))
        guard
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: PixelBuffers.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        draw(context, CGSize(width: width, height: height))
        guard let image = context.makeImage() else { return nil }
        lock.lock()
        images[key] = image
        lock.unlock()
        return image
    }

    /// Draws a cached image into `rect` of a top-left-origin context.
    public func drawImage(_ image: CGImage, in rect: CGRect, context: CGContext) {
        context.saveGState()
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
