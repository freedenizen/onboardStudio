import CoreImage
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit

/// A 64×32 source: left half red, right half blue, top row green.
enum QuadSource {
    static func make() throws -> CVPixelBuffer {
        let buffer = try PixelBuffers.makeBuffer(width: 64, height: 32)
        try PixelBuffers.draw(into: buffer) { cg, _ in
            cg.setFillColor(PixelBuffers.color(red: 1, green: 0, blue: 0))
            cg.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
            cg.setFillColor(PixelBuffers.color(red: 0, green: 0, blue: 1))
            cg.fill(CGRect(x: 32, y: 0, width: 32, height: 32))
            cg.setFillColor(PixelBuffers.color(red: 0, green: 1, blue: 0))
            cg.fill(CGRect(x: 0, y: 0, width: 64, height: 4))
        }
        return buffer
    }
}

@Suite("VideoTransform")
struct VideoTransformTests {
    func render(_ transform: VideoTransform, width: Int = 64, height: Int = 32) throws -> CVPixelBuffer {
        let plan = RenderPlan(
            outputWidth: width, outputHeight: height, frameRate: 30,
            videoLayers: [VideoLayer(trackID: 1, transform: transform)], overlays: [])
        return try FrameCompositor(plan: plan).renderFrame(sources: [1: try QuadSource.make()], time: 0)
    }

    @Test func identityKeepsLayout() throws {
        let frame = try render(.identity)
        #expect(PixelBuffers.pixel(in: frame, x: 8, y: 16).r > 200)
        #expect(PixelBuffers.pixel(in: frame, x: 56, y: 16).b > 200)
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 1).g > 200)
    }

    @Test func mirrorHorizontalSwapsHalves() throws {
        let frame = try render(VideoTransform(mirror: Mirror(horizontal: true)))
        #expect(PixelBuffers.pixel(in: frame, x: 8, y: 16).b > 200)
        #expect(PixelBuffers.pixel(in: frame, x: 56, y: 16).r > 200)
    }

    @Test func mirrorVerticalMovesTopRowToBottom() throws {
        let frame = try render(VideoTransform(mirror: Mirror(vertical: true)))
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 30).g > 200)
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 1).g < 60)
    }

    @Test func rotate90ClockwisePutsTopRowOnTheRight() throws {
        // 64×32 rotated → 32×64, aspect-fitted into a 64×32 output: 16×32 centred at x 24…40.
        let frame = try render(VideoTransform(rotation: 90))
        let rightEdge = PixelBuffers.pixel(in: frame, x: 39, y: 16)
        #expect(rightEdge.g > 200, "top row should end up on the right after clockwise rotation, got \(rightEdge)")
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 4).r > 200)  // left half (red) is now on top
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 28).b > 200)  // right half (blue) now at the bottom
        #expect(PixelBuffers.pixel(in: frame, x: 4, y: 16).r < 30)  // letterbox
    }

    @Test func cropRemovesEdges() throws {
        // Crop the left half away: the remaining 32×32 blue square is aspect-fitted and centred.
        let frame = try render(VideoTransform(crop: CropInsets(left: 0.5)))
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 16).b > 200)
        #expect(PixelBuffers.pixel(in: frame, x: 8, y: 16).b < 30)
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 1).g > 200)  // the green top row survives
    }

    @Test func channelMaskDropsChannels() throws {
        let frame = try render(VideoTransform(channelMask: RGBMask(red: false, green: true, blue: true)))
        let left = PixelBuffers.pixel(in: frame, x: 8, y: 16)
        #expect(left.r < 10 && left.g < 10 && left.b < 10)
        #expect(PixelBuffers.pixel(in: frame, x: 56, y: 16).b > 200)
    }

    @Test func colorAdjustmentsChangeBrightnessAndSaturation() throws {
        let dark = try render(VideoTransform(color: ColorAdjustments(brightness: 0.5)))
        #expect(PixelBuffers.pixel(in: dark, x: 8, y: 16).r < 160)
        let grey = try render(VideoTransform(color: ColorAdjustments(saturation: 0)))
        let p = PixelBuffers.pixel(in: grey, x: 8, y: 16)
        #expect(abs(Int(p.r) - Int(p.g)) < 12 && abs(Int(p.g) - Int(p.b)) < 12)
    }

    @Test func chromaKeyMakesTheKeyColourTransparent() throws {
        // Key out blue: the right half should show the black background; red stays.
        let key = ChromaKey(color: RGBAColor(red: 0, green: 0, blue: 1), tolerance: 0.3, softness: 0.1)
        let frame = try render(VideoTransform(chromaKey: key))
        let right = PixelBuffers.pixel(in: frame, x: 56, y: 16)
        #expect(right.b < 40, "blue should be keyed out, got \(right)")
        #expect(PixelBuffers.pixel(in: frame, x: 8, y: 16).r > 200)
        #expect(PixelBuffers.pixel(in: frame, x: 32, y: 1).g > 150)
    }

    @Test func hsvConversion() {
        let red = ChromaKeyLUT.hsv(r: 1, g: 0, b: 0)
        #expect(abs(red.h) < 1e-9 && red.s == 1 && red.v == 1)
        let green = ChromaKeyLUT.hsv(r: 0, g: 1, b: 0)
        #expect(abs(green.h - 1.0 / 3) < 1e-9)
        let grey = ChromaKeyLUT.hsv(r: 0.5, g: 0.5, b: 0.5)
        #expect(grey.s == 0 && grey.v == 0.5)
    }
}
