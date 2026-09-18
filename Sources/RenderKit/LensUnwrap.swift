import CoreImage
import Foundation
import Metal
import ProjectModel

/// Re-projects a fisheye or 360° (equirectangular) picture into a flat, rectilinear view with a
/// virtual camera (`LensSettings`). Runs as a Core Image processor kernel: on the GPU through a
/// Metal compute function compiled from source at first use (no build-time shaders), or on the
/// CPU with a cached remap table when Core Image renders in software.
public enum LensUnwrap {
    /// Size of the unwrapped picture for a source of `sourceSize`: fisheye keeps the source size,
    /// 360° sources become a 16:9 picture half the source width (a 90° window of the panorama).
    public static func outputSize(for settings: LensSettings, sourceSize: CGSize) -> CGSize {
        switch settings.mode {
        case .none, .fisheye:
            return sourceSize
        case .equirectangular:
            let width = max(2, (sourceSize.width / 2).rounded(.down))
            let height = max(2, (width * 9 / 16).rounded(.down))
            return CGSize(width: width, height: height)
        }
    }

    /// Applies the unwrap; the result's extent starts at the origin. Inactive settings return the source.
    public static func apply(_ settings: LensSettings, to source: CIImage) -> CIImage {
        guard settings.isActive, source.extent.width > 1, source.extent.height > 1 else { return source }
        let extent = source.extent
        let size = outputSize(for: settings, sourceSize: extent.size)
        let arguments: [String: Any] = [
            LensUnwrapKernel.settingsKey: LensParameters(settings: settings, sourceSize: extent.size, outputSize: size),
            LensUnwrapKernel.sourceExtentKey: CIVector(cgRect: extent),
        ]
        do {
            return try LensUnwrapKernel.apply(
                withExtent: CGRect(origin: .zero, size: size), inputs: [source], arguments: arguments)
        } catch {
            return source
        }
    }

    /// The direction (unit vector, camera looks along +z, x right, y up) seen by an output pixel.
    static func rotation(yaw: Double, pitch: Double, roll: Double) -> [Double] {
        let y = yaw * .pi / 180
        let p = -pitch * .pi / 180
        let r = roll * .pi / 180
        // Rz(roll) first, then Rx(-pitch), then Ry(yaw): R = Ry · Rx · Rz (row-major 3×3).
        let ry = [cos(y), 0, sin(y), 0, 1, 0, -sin(y), 0, cos(y)]
        let rx = [1, 0, 0, 0, cos(p), -sin(p), 0, sin(p), cos(p)]
        let rz = [cos(r), -sin(r), 0, sin(r), cos(r), 0, 0, 0, 1]
        return multiply(ry, multiply(rx, rz))
    }

    private static func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        var out = [Double](repeating: 0, count: 9)
        for row in 0..<3 {
            for col in 0..<3 {
                out[row * 3 + col] = a[row * 3] * b[col] + a[row * 3 + 1] * b[3 + col] + a[row * 3 + 2] * b[6 + col]
            }
        }
        return out
    }
}

/// The kernel's constant buffer; layout mirrors `LensParams` in the Metal source (96 bytes).
struct LensParameters: Sendable {
    var r0: SIMD4<Float>
    var r1: SIMD4<Float>
    var r2: SIMD4<Float>
    var sourceSize: SIMD2<Float>
    var outputSize: SIMD2<Float>
    var sourceOrigin: SIMD2<Float>
    var tanHalfOutput: Float
    var halfFov: Float
    var mode: Int32
    var flipInput: Int32
    var flipOutput: Int32
    var padding: Int32 = 0

    init(settings: LensSettings, sourceSize: CGSize, outputSize: CGSize) {
        let m = LensUnwrap.rotation(yaw: settings.yaw, pitch: settings.pitch, roll: settings.roll).map(Float.init)
        r0 = SIMD4(m[0], m[1], m[2], 0)
        r1 = SIMD4(m[3], m[4], m[5], 0)
        r2 = SIMD4(m[6], m[7], m[8], 0)
        self.sourceSize = SIMD2(Float(sourceSize.width), Float(sourceSize.height))
        self.outputSize = SIMD2(Float(outputSize.width), Float(outputSize.height))
        sourceOrigin = .zero
        tanHalfOutput = Float(tan(min(max(settings.outputFov, 10), 170) / 2 * .pi / 180))
        halfFov = Float(min(max(settings.fov, 30), 360) / 2 * .pi / 180)
        mode = settings.mode == .equirectangular ? 2 : 1
        flipInput = 0
        flipOutput = 0
    }

    /// Source pixel (top-left origin, in source pixels) seen by output pixel centre (`x`, `y`)
    /// measured from the top-left; `nil` when the ray leaves the source picture.
    func sourcePoint(x: Float, y: Float) -> SIMD2<Float>? {
        let halfWidth = outputSize.x / 2
        let vx = (x - halfWidth) / halfWidth * tanHalfOutput
        let vy = (outputSize.y / 2 - y) / halfWidth * tanHalfOutput
        let v = SIMD3<Float>(vx, vy, 1)
        var d = SIMD3<Float>(
            r0.x * v.x + r0.y * v.y + r0.z * v.z, r1.x * v.x + r1.y * v.y + r1.z * v.z,
            r2.x * v.x + r2.y * v.y + r2.z * v.z)
        d /= (d * d).sum().squareRoot()
        if mode == 2 {
            let lon = atan2(d.x, d.z)
            let lat = asin(max(-1, min(1, d.y)))
            return SIMD2((lon / (2 * .pi) + 0.5) * sourceSize.x, (0.5 - lat / .pi) * sourceSize.y)
        }
        let theta = acos(max(-1, min(1, d.z)))
        guard theta <= halfFov else { return nil }
        let radius = theta / halfFov * sourceSize.x / 2
        let phi = atan2(d.y, d.x)
        return SIMD2(sourceSize.x / 2 + cos(phi) * radius, sourceSize.y / 2 - sin(phi) * radius)
    }
}

/// Core Image processor kernel wrapping the Metal function (GPU) or a CPU remap.
final class LensUnwrapKernel: CIImageProcessorKernel {
    static let settingsKey = "lens"
    static let sourceExtentKey = "sourceExtent"

    override static var outputFormat: CIFormat { .BGRA8 }
    override static func formatForInput(at input: Int32) -> CIFormat { .BGRA8 }

    override static func roi(forInput input: Int32, arguments: [String: Any]?, outputRect: CGRect) -> CGRect {
        (arguments?[sourceExtentKey] as? CIVector)?.cgRectValue ?? outputRect
    }

    override static func process(
        with inputs: [CIImageProcessorInput]?, arguments: [String: Any]?, output: CIImageProcessorOutput
    ) throws {
        guard let input = inputs?.first, var parameters = arguments?[settingsKey] as? LensParameters,
            let extent = (arguments?[sourceExtentKey] as? CIVector)?.cgRectValue
        else { throw LensUnwrapError.badArguments }
        // The input region may be larger than the source picture; remember where the picture starts.
        parameters.sourceOrigin = SIMD2(
            Float(extent.minX - input.region.minX), Float(input.region.maxY - extent.maxY))
        if let source = input.metalTexture, let target = output.metalTexture,
            let commandBuffer = output.metalCommandBuffer
        {
            try MetalUnwrap.encode(source: source, target: target, parameters: parameters, on: commandBuffer)
        } else {
            try CPUUnwrap.run(input: input, output: output, parameters: parameters, extent: extent)
        }
    }
}

enum LensUnwrapError: Error {
    case badArguments
    case noMetalFunction
    case noEncoder
}

/// Compiles the compute function once per device and dispatches it.
enum MetalUnwrap {
    nonisolated(unsafe) private static var pipelines: [ObjectIdentifier: MTLComputePipelineState] = [:]
    private static let lock = NSLock()

    static func pipeline(for device: MTLDevice) throws -> MTLComputePipelineState {
        lock.lock()
        defer { lock.unlock() }
        if let cached = pipelines[ObjectIdentifier(device)] { return cached }
        let library = try device.makeLibrary(source: source, options: nil)
        guard let function = library.makeFunction(name: "lensUnwrap") else { throw LensUnwrapError.noMetalFunction }
        let pipeline = try device.makeComputePipelineState(function: function)
        pipelines[ObjectIdentifier(device)] = pipeline
        return pipeline
    }

    static func encode(
        source: MTLTexture, target: MTLTexture, parameters: LensParameters, on commandBuffer: MTLCommandBuffer
    ) throws {
        let pipeline = try pipeline(for: commandBuffer.device)
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { throw LensUnwrapError.noEncoder }
        var params = parameters
        // Core Image hands Metal textures with row 0 at the top of the region.
        params.flipInput = 0
        params.flipOutput = 0
        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(source, index: 0)
        encoder.setTexture(target, index: 1)
        encoder.setBytes(&params, length: MemoryLayout<LensParameters>.stride, index: 0)
        let w = pipeline.threadExecutionWidth
        let h = max(1, pipeline.maxTotalThreadsPerThreadgroup / w)
        let groups = MTLSize(width: (target.width + w - 1) / w, height: (target.height + h - 1) / h, depth: 1)
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: MTLSize(width: w, height: h, depth: 1))
        encoder.endEncoding()
    }

    static let source = """
        #include <metal_stdlib>
        using namespace metal;

        struct LensParams {
            float4 r0; float4 r1; float4 r2;
            float2 sourceSize; float2 outputSize; float2 sourceOrigin;
            float tanHalfOutput; float halfFov;
            int mode; int flipInput; int flipOutput; int padding;
        };

        kernel void lensUnwrap(texture2d<float, access::sample> src [[texture(0)]],
                               texture2d<float, access::write> dst [[texture(1)]],
                               constant LensParams &p [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
            if (gid.x >= dst.get_width() || gid.y >= dst.get_height()) { return; }
            constexpr sampler smp(coord::pixel, address::clamp_to_zero, filter::linear);
            float outY = p.flipOutput ? (p.outputSize.y - 1.0 - float(gid.y)) : float(gid.y);
            float halfWidth = p.outputSize.x * 0.5;
            float vx = ((float(gid.x) + 0.5) - halfWidth) / halfWidth * p.tanHalfOutput;
            float vy = (p.outputSize.y * 0.5 - (outY + 0.5)) / halfWidth * p.tanHalfOutput;
            float3 v = float3(vx, vy, 1.0);
            float3 d = normalize(float3(dot(p.r0.xyz, v), dot(p.r1.xyz, v), dot(p.r2.xyz, v)));
            float2 s;
            if (p.mode == 2) {
                float lon = atan2(d.x, d.z);
                float lat = asin(clamp(d.y, -1.0, 1.0));
                s = float2((lon / (2.0 * M_PI_F) + 0.5) * p.sourceSize.x, (0.5 - lat / M_PI_F) * p.sourceSize.y);
            } else {
                float theta = acos(clamp(d.z, -1.0, 1.0));
                if (theta > p.halfFov) { dst.write(float4(0.0), gid); return; }
                float radius = theta / p.halfFov * p.sourceSize.x * 0.5;
                float phi = atan2(d.y, d.x);
                s = float2(p.sourceSize.x * 0.5 + cos(phi) * radius, p.sourceSize.y * 0.5 - sin(phi) * radius);
            }
            float2 texel = s + p.sourceOrigin;
            if (p.flipInput) { texel.y = float(src.get_height()) - texel.y; }
            float4 color = src.sample(smp, texel);
            dst.write(color, gid);
        }
        """
}

/// Bilinear remap on the CPU through a cached table of source coordinates per output pixel.
enum CPUUnwrap {
    nonisolated(unsafe) private static var tables: [String: [SIMD2<Float>]] = [:]
    private static let lock = NSLock()

    static func table(for parameters: LensParameters) -> [SIMD2<Float>] {
        let key =
            "\(parameters.r0)\(parameters.r1)\(parameters.r2)\(parameters.sourceSize)\(parameters.outputSize)"
            + "\(parameters.tanHalfOutput)\(parameters.halfFov)\(parameters.mode)"
        lock.lock()
        if let cached = tables[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let width = Int(parameters.outputSize.x)
        let height = Int(parameters.outputSize.y)
        var built = [SIMD2<Float>](repeating: SIMD2(-1, -1), count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                if let p = parameters.sourcePoint(x: Float(x) + 0.5, y: Float(y) + 0.5) { built[y * width + x] = p }
            }
        }
        lock.lock()
        tables[key] = built
        lock.unlock()
        return built
    }

    static func run(
        input: CIImageProcessorInput, output: CIImageProcessorOutput, parameters: LensParameters, extent: CGRect
    ) throws {
        let table = table(for: parameters)
        let outWidth = Int(parameters.outputSize.x)
        let outHeight = Int(parameters.outputSize.y)
        let inWidth = Int(input.region.width)
        let inHeight = Int(input.region.height)
        let src = input.baseAddress.assumingMemoryBound(to: UInt8.self)
        let dst = output.baseAddress.assumingMemoryBound(to: UInt8.self)
        let srcRow = input.bytesPerRow
        let dstRow = output.bytesPerRow
        // Only the requested tile of the output is present; it may be smaller than the whole picture.
        let tileX = Int(output.region.minX)
        let tileY = Int(output.region.minY)
        let tileWidth = Int(output.region.width)
        let tileHeight = Int(output.region.height)
        // Bitmaps from Core Image have row 0 at the bottom of the region (lowest y), so a row
        // index counts up from the bottom of the picture on both sides.
        let inputTop = Float(input.region.maxY) - Float(extent.maxY)
        let inputRows = Float(inHeight)
        for ty in 0..<tileHeight {
            let y = outHeight - 1 - (tileY + ty)
            guard y >= 0, y < outHeight else { continue }
            for tx in 0..<tileWidth {
                let x = tileX + tx
                guard x >= 0, x < outWidth else { continue }
                let p = table[y * outWidth + x]
                let dstPixel = dst + ty * dstRow + tx * 4
                guard p.x >= 0 else {
                    dstPixel.update(repeating: 0, count: 4)
                    continue
                }
                let sx = p.x + parameters.sourceOrigin.x - 0.5
                let sy = inputRows - (p.y + inputTop) - 0.5
                let x0 = Int(sx.rounded(.down))
                let y0 = Int(sy.rounded(.down))
                let fx = sx - Float(x0)
                let fy = sy - Float(y0)
                var accumulated = SIMD4<Float>(repeating: 0)
                for (dy, wy) in [(0, 1 - fy), (1, fy)] {
                    let yy = y0 + dy
                    guard yy >= 0, yy < inHeight, wy > 0 else { continue }
                    for (dx, wx) in [(0, 1 - fx), (1, fx)] {
                        let xx = x0 + dx
                        guard xx >= 0, xx < inWidth, wx > 0 else { continue }
                        let s = src + yy * srcRow + xx * 4
                        let weight = wx * wy
                        accumulated += SIMD4(Float(s[0]), Float(s[1]), Float(s[2]), Float(s[3])) * weight
                    }
                }
                for channel in 0..<4 { dstPixel[channel] = UInt8(min(255, max(0, accumulated[channel].rounded()))) }
            }
        }
    }
}
