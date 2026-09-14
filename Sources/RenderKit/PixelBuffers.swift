import CoreGraphics
import CoreVideo
import Foundation

public enum PixelBufferError: Error, CustomStringConvertible {
    case allocationFailed(CVReturn)
    case contextFailed

    public var description: String {
        switch self {
        case .allocationFailed(let code): "Could not allocate pixel buffer (CVReturn \(code))."
        case .contextFailed: "Could not create a drawing context for the pixel buffer."
        }
    }
}

/// One BGRA pixel read back from a buffer, components in 0…255 (alpha premultiplied).
public struct Pixel: Equatable, Sendable, CustomStringConvertible {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public var description: String { "(r: \(r), g: \(g), b: \(b), a: \(a))" }
}

/// Helpers for BGRA pixel buffers used by the overlay renderer and tests. All drawing uses the
/// sRGB colour space so CGColor components, Core Image and the encoder agree.
public enum PixelBuffers {
    public static let pixelFormat = kCVPixelFormatType_32BGRA
    public static let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()

    /// An sRGB colour from 0…1 components.
    public static func color(red: Double, green: Double, blue: Double, alpha: Double = 1) -> CGColor {
        CGColor(colorSpace: colorSpace, components: [red, green, blue, alpha]) ?? CGColor(gray: 0, alpha: alpha)
    }

    /// Creates a pool of BGRA buffers of the given size, backed by IOSurface for Core Image.
    public static func makePool(width: Int, height: Int) throws -> CVPixelBufferPool {
        let attributes: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: pixelFormat,
            kCVPixelBufferWidthKey: width,
            kCVPixelBufferHeightKey: height,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        var pool: CVPixelBufferPool?
        let status = CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
        guard status == kCVReturnSuccess, let pool else { throw PixelBufferError.allocationFailed(status) }
        return pool
    }

    public static func makeBuffer(from pool: CVPixelBufferPool) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
        guard status == kCVReturnSuccess, let buffer else { throw PixelBufferError.allocationFailed(status) }
        return buffer
    }

    public static func makeBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        try makeBuffer(from: try makePool(width: width, height: height))
    }

    /// Runs `body` with a CGContext drawing directly into `buffer`, origin at the top-left.
    /// The buffer is cleared to transparent first.
    public static func draw(into buffer: CVPixelBuffer, _ body: (CGContext, CGSize) throws -> Void) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard let base = CVPixelBufferGetBaseAddress(buffer),
            let context = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { throw PixelBufferError.contextFailed }
        context.clear(CGRect(x: 0, y: 0, width: width, height: height))
        // Flip so that y grows downward, matching video and SwiftUI conventions.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: 1, y: -1)
        try body(context, CGSize(width: width, height: height))
    }

    /// Reads one pixel. Alpha is premultiplied.
    public static func pixel(in buffer: CVPixelBuffer, x: Int, y: Int) -> Pixel {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return Pixel(r: 0, g: 0, b: 0, a: 0) }
        let row = CVPixelBufferGetBytesPerRow(buffer)
        let p = base.advanced(by: y * row + x * 4).assumingMemoryBound(to: UInt8.self)
        return Pixel(r: p[2], g: p[1], b: p[0], a: p[3])
    }

    /// Fills the whole buffer with one opaque colour (used by tests to make synthetic sources).
    public static func fill(_ buffer: CVPixelBuffer, red: Double, green: Double, blue: Double) throws {
        try draw(into: buffer) { context, size in
            context.setFillColor(color(red: red, green: green, blue: blue))
            context.fill(CGRect(origin: .zero, size: size))
        }
    }
}
