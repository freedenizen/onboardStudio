import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers

@testable import RenderKit

/// Compares rendered frames against PNGs in `Tests/Fixtures/Goldens`. Set `UPDATE_GOLDENS=1` to
/// rewrite them. Text anti-aliasing differs slightly between OS versions, so a small per-pixel
/// tolerance and a differing-pixel budget are allowed.
enum GoldenImage {
    static var goldensDirectory: URL {
        // Tests/RenderKitTests/GoldenImage.swift → Tests/Fixtures/Goldens
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(
            path: "Fixtures/Goldens")
    }

    static var shouldUpdate: Bool { ProcessInfo.processInfo.environment["UPDATE_GOLDENS"] == "1" }

    static func image(from buffer: CVPixelBuffer) -> CGImage? {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
            let context = CGContext(
                data: base, width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: PixelBuffers.colorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue)
        else { return nil }
        return context.makeImage()
    }

    static func write(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw GoldenError.cannotWrite(url)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw GoldenError.cannotWrite(url) }
    }

    static func read(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// RGBA8 bytes in a known layout for comparison.
    static func rgba(_ image: CGImage) -> [UInt8]? {
        let width = image.width
        let height = image.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let ok = data.withUnsafeMutableBytes { raw -> Bool in
            guard
                let context = CGContext(
                    data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: PixelBuffers.colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return ok ? data : nil
    }

    /// Asserts `buffer` matches the golden named `name`, or records it when updating.
    static func assertMatches(
        _ buffer: CVPixelBuffer, named name: String, tolerance: UInt8 = 24, maxDifferentFraction: Double = 0.01
    ) throws {
        let url = goldensDirectory.appending(path: "\(name).png")
        let actual = try #require(Self.image(from: buffer))
        if shouldUpdate || !FileManager.default.fileExists(atPath: url.path) {
            try write(actual, to: url)
            Issue.record("Golden \(name).png was (re)generated; re-run without UPDATE_GOLDENS to compare.")
            return
        }
        let expected = try #require(read(url))
        #expect(expected.width == actual.width && expected.height == actual.height, "size mismatch for \(name)")
        let a = try #require(rgba(actual))
        let b = try #require(rgba(expected))
        var different = 0
        var maxDiff = 0
        for index in stride(from: 0, to: min(a.count, b.count), by: 4) {
            var pixelDiff = 0
            for channel in 0..<4 { pixelDiff = max(pixelDiff, abs(Int(a[index + channel]) - Int(b[index + channel]))) }
            maxDiff = max(maxDiff, pixelDiff)
            if pixelDiff > Int(tolerance) { different += 1 }
        }
        let fraction = Double(different) / Double(max(1, a.count / 4))
        if fraction > maxDifferentFraction {
            let actualURL = FileManager.default.temporaryDirectory.appending(path: "\(name)-actual.png")
            try? write(actual, to: actualURL)
            let percent = String(format: "%.2f", fraction * 100)
            Issue.record(
                "\(name): \(percent)% of pixels differ by >\(tolerance) (max \(maxDiff)); see \(actualURL.path)"
            )
        }
    }

    enum GoldenError: Error {
        case cannotWrite(URL)
    }
}
