import CoreGraphics
import CoreVideo
import Foundation
import Testing

@testable import RenderKit

/// What a rejected golden reports (#447): how much differs, by how much, and where — the part a
/// percentage alone never said.
@Suite("What a rejected golden reports")
struct GoldenDifferenceTests {
    /// A black frame with one filled rectangle.
    func buffer(with rect: CGRect, gray: Double = 1) throws -> CVPixelBuffer {
        let buffer = try PixelBuffers.makeBuffer(width: 40, height: 30)
        try PixelBuffers.draw(into: buffer) { context, size in
            context.setFillColor(PixelBuffers.color(red: 0, green: 0, blue: 0))
            context.fill(CGRect(origin: .zero, size: size))
            context.setFillColor(PixelBuffers.color(red: gray, green: gray, blue: gray))
            context.fill(rect)
        }
        return buffer
    }

    func frame(with rect: CGRect, gray: Double = 1) throws -> CGImage {
        try #require(GoldenImage.image(from: try buffer(with: rect, gray: gray)))
    }

    static let shape = CGRect(x: 4, y: 5, width: 10, height: 6)
    static let moved = CGRect(x: 5, y: 5, width: 10, height: 6)

    func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "golden-difference-\(UUID().uuidString)")
    }

    @Test func theSameFrameDiffersNowhere() throws {
        let image = try frame(with: Self.shape)
        let found = try #require(GoldenImage.difference(image, image, tolerance: 24))
        #expect(found.different == 0 && found.maximum == 0 && found.fraction == 0)
        #expect(found.place == "nowhere")
    }

    @Test func aMovedShapeIsCountedAndPlaced() throws {
        // The rectangle one pixel to the right: a column leaves on the left and one arrives on the
        // right, six rows each, from the top-left corner of the frame.
        let expected = try frame(with: Self.shape)
        let actual = try frame(with: Self.moved)
        let found = try #require(GoldenImage.difference(actual, expected, tolerance: 24))
        #expect(found.different == 12 && found.total == 1200)
        #expect(found.maximum == 255)
        #expect(found.percent == "1.00")
        #expect(found.place == "x 4…14, y 5…10 of 40×30")
        // The picture of the difference is white exactly there.
        let picture = try #require(GoldenImage.picture(of: found))
        #expect(picture.width == 40 && picture.height == 30)
        #expect(found.mask.filter { $0 == 255 }.count == 12)
        #expect(found.mask[5 * 40 + 4] == 255 && found.mask[5 * 40 + 14] == 255 && found.mask[5 * 40 + 9] == 0)
    }

    @Test func aDifferenceWithinTheToleranceIsMeasuredButNotCounted() throws {
        let expected = try frame(with: Self.shape, gray: 0.5)
        let actual = try frame(with: Self.shape, gray: 0.55)
        let found = try #require(GoldenImage.difference(actual, expected, tolerance: 24))
        #expect(found.different == 0 && found.maximum > 0 && found.maximum <= 24)
        #expect(found.place == "nowhere")
    }

    @Test func aFrameWithinTheBudgetLeavesNothing() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let image = try frame(with: Self.shape)
        let comparison = GoldenImage.Comparison(name: "shape", directory: directory)
        #expect(GoldenImage.rejection(of: image, against: image, comparison) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func aRejectedFrameIsKeptWithAPictureOfWhereItDiffers() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = try frame(with: Self.shape)
        // No pixel may differ, so the moved shape's twelve are too many.
        let comparison = GoldenImage.Comparison(name: "shape", maxDifferentFraction: 0, directory: directory)
        let message = try #require(
            GoldenImage.rejection(of: try frame(with: Self.moved), against: expected, comparison))
        let kept = directory.appending(path: "shape-actual.png")
        #expect(
            message
                == "shape: 1.00% of pixels differ by >24 (max 255), within x 4…14, y 5…10 of 40×30; see \(kept.path)")
        // The frame that was rejected, not the golden; and the picture is the size of the frame.
        let actual = try #require(GoldenImage.read(kept))
        #expect(try #require(GoldenImage.difference(actual, expected, tolerance: 24)).different == 12)
        let picture = try #require(GoldenImage.read(directory.appending(path: "shape-difference.png")))
        #expect(picture.width == 40 && picture.height == 30)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "shape-actual-second.png").path))
    }

    @Test func aSecondRenderThatMatchesIsSaidToMatch() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = try frame(with: Self.shape)
        let comparison = GoldenImage.Comparison(name: "shape", maxDifferentFraction: 0, directory: directory)
        var asked = 0
        let message = try #require(
            GoldenImage.rejection(of: try frame(with: Self.moved), against: expected, comparison) {
                asked += 1
                return try buffer(with: Self.shape)
            })
        #expect(asked == 1)
        #expect(message.contains("; rendered again it matches, so the first render was not repeatable; see "))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "shape-actual-second.png").path))
    }

    @Test func aSecondRenderThatDiffersTooIsKeptAsWell() throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let expected = try frame(with: Self.shape)
        let comparison = GoldenImage.Comparison(name: "shape", maxDifferentFraction: 0, directory: directory)
        let message = try #require(
            GoldenImage.rejection(of: try frame(with: Self.moved), against: expected, comparison) {
                try buffer(with: Self.moved)
            })
        #expect(message.contains("; rendered again it differs by 1.00% (max 255); see "))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "shape-actual-second.png").path))
    }

    @Test func aFrameThatMatchesIsNotRenderedAgain() throws {
        let image = try frame(with: Self.shape)
        var asked = 0
        let comparison = GoldenImage.Comparison(name: "shape", directory: temporaryDirectory())
        let message = GoldenImage.rejection(of: image, against: image, comparison) {
            asked += 1
            return try buffer(with: Self.shape)
        }
        #expect(message == nil && asked == 0)
    }
}
