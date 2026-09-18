import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import ProjectModel

/// Per-layer picture processing applied with Core Image: crop, rotation, mirror, colour
/// adjustments, chroma key and channel mask. Pure value; the LUT for chroma keying is cached.
public struct VideoTransform: Sendable, Hashable {
    public var crop: CropInsets
    public var rotation: Double
    public var mirror: Mirror
    public var color: ColorAdjustments
    public var chromaKey: ChromaKey?
    public var channelMask: RGBMask
    /// Fisheye / 360° unwrap, applied before everything else.
    public var lens: LensSettings

    public init(
        lens: LensSettings = .none,
        crop: CropInsets = .none,
        rotation: Double = 0,
        mirror: Mirror = .none,
        color: ColorAdjustments = .neutral,
        chromaKey: ChromaKey? = nil,
        channelMask: RGBMask = .all
    ) {
        self.lens = lens
        self.crop = crop
        self.rotation = rotation
        self.mirror = mirror
        self.color = color
        self.chromaKey = chromaKey
        self.channelMask = channelMask
    }

    public static let identity = VideoTransform()
    public var isIdentity: Bool { self == .identity }

    /// Applies the transform. The result's extent starts at the origin.
    public func apply(to source: CIImage) -> CIImage {
        var image = LensUnwrap.apply(lens, to: source)
        if !crop.isEmpty {
            let e = image.extent
            let rect = CGRect(
                x: e.minX + e.width * crop.left,
                y: e.minY + e.height * crop.bottom,
                width: e.width * max(0, 1 - crop.left - crop.right),
                height: e.height * max(0, 1 - crop.top - crop.bottom))
            image = image.cropped(to: rect)
        }
        if !color.isNeutral {
            image = image.applyingFilter(
                "CIColorControls",
                parameters: [
                    kCIInputBrightnessKey: color.brightness - 1,
                    kCIInputContrastKey: color.contrast,
                    kCIInputSaturationKey: color.saturation,
                ])
            if color.hue != 0 {
                image = image.applyingFilter("CIHueAdjust", parameters: [kCIInputAngleKey: color.hue * .pi / 180])
            }
            if color.sharpness != 1 {
                image = image.applyingFilter(
                    "CISharpenLuminance", parameters: [kCIInputSharpnessKey: (color.sharpness - 1) * 2])
            }
        }
        if let chromaKey {
            image = image.applyingFilter(
                "CIColorCube",
                parameters: [
                    "inputCubeDimension": ChromaKeyLUT.dimension,
                    "inputCubeData": ChromaKeyLUT.data(for: chromaKey),
                ])
        }
        if !channelMask.isAll {
            image = image.applyingFilter(
                "CIColorMatrix",
                parameters: [
                    "inputRVector": CIVector(x: channelMask.red ? 1 : 0, y: 0, z: 0, w: 0),
                    "inputGVector": CIVector(x: 0, y: channelMask.green ? 1 : 0, z: 0, w: 0),
                    "inputBVector": CIVector(x: 0, y: 0, z: channelMask.blue ? 1 : 0, w: 0),
                ])
        }
        var transform = CGAffineTransform.identity
        if mirror.horizontal { transform = transform.scaledBy(x: -1, y: 1) }
        if mirror.vertical { transform = transform.scaledBy(x: 1, y: -1) }
        if rotation != 0 {
            // Core Image rotates counter-clockwise for positive angles; our rotation is clockwise.
            transform = transform.rotated(by: -rotation * .pi / 180)
        }
        if transform != .identity {
            image = image.transformed(by: transform)
        }
        // Normalise the origin so placement maths can assume (0, 0).
        let extent = image.extent
        if extent.minX != 0 || extent.minY != 0 {
            image = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
        }
        return image
    }
}

/// Builds and caches `CIColorCube` lookup tables that make a colour range transparent.
enum ChromaKeyLUT {
    static let dimension = 32
    nonisolated(unsafe) private static var cache: [ChromaKey: Data] = [:]
    private static let lock = NSLock()

    static func data(for key: ChromaKey) -> Data {
        lock.lock()
        if let cached = cache[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let built = build(key)
        lock.lock()
        cache[key] = built
        lock.unlock()
        return built
    }

    private static func build(_ key: ChromaKey) -> Data {
        let n = dimension
        var cube = [Float](repeating: 0, count: n * n * n * 4)
        let target = hsv(r: key.color.red, g: key.color.green, b: key.color.blue)
        let tolerance = max(0.001, key.tolerance)
        let soft = max(0, key.softness)
        var index = 0
        for b in 0..<n {
            for g in 0..<n {
                for r in 0..<n {
                    let rf = Double(r) / Double(n - 1)
                    let gf = Double(g) / Double(n - 1)
                    let bf = Double(b) / Double(n - 1)
                    let sample = hsv(r: rf, g: gf, b: bf)
                    // Hue distance wraps; weight hue most, then saturation/value.
                    var dh = abs(sample.h - target.h)
                    dh = min(dh, 1 - dh) * 2
                    let ds = abs(sample.s - target.s)
                    let dv = abs(sample.v - target.v)
                    let distance = sqrt(dh * dh * 2 + ds * ds + dv * dv * 0.5)
                    // Very dark or very grey pixels are never keyed (their hue is meaningless).
                    let keyable = sample.s > 0.15 && sample.v > 0.15
                    var alpha: Double = 1
                    if keyable {
                        if distance <= tolerance {
                            alpha = 0
                        } else if soft > 0, distance < tolerance + soft {
                            alpha = (distance - tolerance) / soft
                        }
                    }
                    // Premultiplied output.
                    cube[index] = Float(rf * alpha)
                    cube[index + 1] = Float(gf * alpha)
                    cube[index + 2] = Float(bf * alpha)
                    cube[index + 3] = Float(alpha)
                    index += 4
                }
            }
        }
        return cube.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    struct HSV {
        let h: Double
        let s: Double
        let v: Double
    }

    static func hsv(r: Double, g: Double, b: Double) -> HSV {
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let delta = maxC - minC
        var h = 0.0
        if delta > 0 {
            if maxC == r {
                h = ((g - b) / delta).truncatingRemainder(dividingBy: 6)
            } else if maxC == g {
                h = (b - r) / delta + 2
            } else {
                h = (r - g) / delta + 4
            }
            h /= 6
            if h < 0 { h += 1 }
        }
        let s = maxC > 0 ? delta / maxC : 0
        return HSV(h: h, s: s, v: maxC)
    }
}
