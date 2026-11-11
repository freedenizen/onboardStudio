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
///
/// A frame that is rejected is kept, with a picture of where it differs, in `GOLDEN_FAILURES_DIR`
/// (the temporary directory when that is not set). CI sets it and uploads the folder when the
/// Test job fails (#447: two goldens had failed there with nothing left to look at).
enum GoldenImage {
    /// Where a rejected frame and its difference picture are written.
    static var failuresDirectory: URL {
        if let path = ProcessInfo.processInfo.environment["GOLDEN_FAILURES_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.temporaryDirectory
    }

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

    /// How a frame differs from its golden: how many pixels, by how much at most, and where.
    struct Difference {
        var different = 0
        var total = 1
        var maximum = 0
        /// The smallest rectangle holding every differing pixel, top-left origin; `maxX` stays
        /// below `minX` while there is none.
        var minX = Int.max
        var minY = Int.max
        var maxX = -1
        var maxY = -1
        /// One byte per pixel, 255 where the pixel differs by more than the tolerance.
        var mask: [UInt8] = []
        var width = 0
        var height = 0

        var fraction: Double { Double(different) / Double(max(1, total)) }
        var percent: String { String(format: "%.2f", fraction * 100) }
        /// "x 20…379, y 21…378 of 400×400"
        var place: String {
            guard maxX >= minX else { return "nowhere" }
            return "x \(minX)…\(maxX), y \(minY)…\(maxY) of \(width)×\(height)"
        }
    }

    static func difference(_ actual: CGImage, _ expected: CGImage, tolerance: UInt8) -> Difference? {
        guard let a = rgba(actual), let b = rgba(expected) else { return nil }
        let width = actual.width
        var result = Difference(total: max(1, a.count / 4), width: width, height: actual.height)
        result.mask = [UInt8](repeating: 0, count: a.count / 4)
        for index in stride(from: 0, to: min(a.count, b.count), by: 4) {
            var pixelDiff = 0
            for channel in 0..<4 { pixelDiff = max(pixelDiff, abs(Int(a[index + channel]) - Int(b[index + channel]))) }
            result.maximum = max(result.maximum, pixelDiff)
            guard pixelDiff > Int(tolerance) else { continue }
            result.different += 1
            let pixel = index / 4
            result.mask[pixel] = 255
            let x = pixel % width
            let y = pixel / width
            result.minX = min(result.minX, x)
            result.maxX = max(result.maxX, x)
            result.minY = min(result.minY, y)
            result.maxY = max(result.maxY, y)
        }
        return result
    }

    /// White where the frame differs from its golden, black elsewhere.
    static func picture(of difference: Difference) -> CGImage? {
        guard difference.width > 0, difference.height > 0,
            let provider = CGDataProvider(data: Data(difference.mask) as CFData)
        else { return nil }
        return CGImage(
            width: difference.width, height: difference.height, bitsPerComponent: 8, bitsPerPixel: 8,
            bytesPerRow: difference.width, space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue), provider: provider, decode: nil,
            shouldInterpolate: false, intent: .defaultIntent)
    }

    /// One comparison: the golden's name, what counts as a difference, and where a rejected
    /// frame is kept.
    struct Comparison {
        var name: String
        var tolerance: UInt8 = 24
        var maxDifferentFraction = 0.01
        var directory = GoldenImage.failuresDirectory
    }

    /// What there is to say about `actual` against `expected`: `nil` when it is within the
    /// budget. A rejected frame is kept in the comparison's directory with a picture of where it
    /// differs, and when `again` is given the frame is rendered a second time and the report says
    /// whether that one matched.
    static func rejection(
        of actual: CGImage, against expected: CGImage, _ comparison: Comparison,
        again: (() throws -> CVPixelBuffer)? = nil
    ) -> String? {
        let name = comparison.name
        guard let found = difference(actual, expected, tolerance: comparison.tolerance) else {
            return "\(name): the frames could not be read"
        }
        guard found.fraction > comparison.maxDifferentFraction else { return nil }
        let actualURL = comparison.directory.appending(path: "\(name)-actual.png")
        try? write(actual, to: actualURL)
        if let picture = picture(of: found) {
            try? write(picture, to: comparison.directory.appending(path: "\(name)-difference.png"))
        }
        var message =
            "\(name): \(found.percent)% of pixels differ by >\(comparison.tolerance) (max \(found.maximum)), "
            + "within \(found.place)"
        if let again, let second = try? again(), let image = Self.image(from: second),
            let secondFound = difference(image, expected, tolerance: comparison.tolerance)
        {
            if secondFound.fraction > comparison.maxDifferentFraction {
                try? write(image, to: comparison.directory.appending(path: "\(name)-actual-second.png"))
                message += "; rendered again it differs by \(secondFound.percent)% (max \(secondFound.maximum))"
            } else {
                message += "; rendered again it matches, so the first render was not repeatable"
            }
        }
        return "\(message); see \(actualURL.path)"
    }

    /// Asserts `buffer` matches the golden named `name`, or records it when updating.
    ///
    /// `again` renders the same frame a second time. It is asked only when the first is rejected,
    /// and only adds to what is reported — whether the second render matched — so a difference
    /// that comes and goes within one run reads apart from one that is always there. A frame
    /// that was rejected fails the test whatever the second one does.
    static func assertMatches(
        _ buffer: CVPixelBuffer, named name: String, tolerance: UInt8 = 24, maxDifferentFraction: Double = 0.01,
        again: (() throws -> CVPixelBuffer)? = nil
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
        let comparison = Comparison(name: name, tolerance: tolerance, maxDifferentFraction: maxDifferentFraction)
        if let message = rejection(of: actual, against: expected, comparison, again: again) {
            Issue.record("\(message)")
        }
    }

    enum GoldenError: Error {
        case cannotWrite(URL)
    }
}
