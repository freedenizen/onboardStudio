import CoreGraphics
import CoreVideo
import Testing

@testable import ProjectModel
@testable import RenderKit

/// Draws a solid rectangle; lets tests verify overlay placement and compositing.
struct SolidOverlay: OverlayDrawing {
    var rect: UnitRect
    var red: Double
    var green: Double
    var blue: Double

    func draw(in context: CGContext, size: CGSize, time: Double) {
        context.setFillColor(PixelBuffers.color(red: red, green: green, blue: blue))
        context.fill(rect.scaled(toWidth: size.width, height: size.height))
    }
}

@Suite("FrameCompositor")
struct FrameCompositorTests {
    func plan(videoLayers: [VideoLayer] = [], overlays: [any OverlayDrawing] = []) -> RenderPlan {
        RenderPlan(outputWidth: 64, outputHeight: 32, frameRate: 30, videoLayers: videoLayers, overlays: overlays)
    }

    @Test func emptyPlanRendersBlack() throws {
        let compositor = try FrameCompositor(plan: plan())
        let frame = try compositor.renderFrame(sources: [:], time: 0)
        let pixel = PixelBuffers.pixel(in: frame, x: 10, y: 10)
        #expect(pixel.r == 0 && pixel.g == 0 && pixel.b == 0 && pixel.a == 255)
    }

    @Test func videoLayerIsAspectFittedIntoItsFrame() throws {
        // A 16x16 red source into a 64x32 output, full frame: letterboxed to 32x32 centred → x 16…48.
        let source = try PixelBuffers.makeBuffer(width: 16, height: 16)
        try PixelBuffers.fill(source, red: 1, green: 0, blue: 0)
        let compositor = try FrameCompositor(plan: plan(videoLayers: [VideoLayer(trackID: 1)]))
        let frame = try compositor.renderFrame(sources: [1: source], time: 0)
        let inside = PixelBuffers.pixel(in: frame, x: 32, y: 16)
        let outside = PixelBuffers.pixel(in: frame, x: 4, y: 16)
        #expect(inside.r > 200 && inside.g < 30 && inside.b < 30)
        #expect(outside.r < 30 && outside.g < 30 && outside.b < 30)
    }

    @Test func videoLayerHonoursUnitFrameWithTopLeftOrigin() throws {
        // Place a 16x8 green source in the bottom-right quarter (x 0.5…1, y 0.5…1).
        let source = try PixelBuffers.makeBuffer(width: 16, height: 8)
        try PixelBuffers.fill(source, red: 0, green: 1, blue: 0)
        let layer = VideoLayer(trackID: 7, frame: UnitRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let compositor = try FrameCompositor(plan: plan(videoLayers: [layer]))
        let frame = try compositor.renderFrame(sources: [7: source], time: 0)
        let bottomRight = PixelBuffers.pixel(in: frame, x: 48, y: 24)
        let topLeft = PixelBuffers.pixel(in: frame, x: 16, y: 8)
        #expect(bottomRight.g > 200)
        #expect(topLeft.g < 30)
    }

    @Test func missingSourceLeavesLayerBlank() throws {
        let compositor = try FrameCompositor(plan: plan(videoLayers: [VideoLayer(trackID: 3)]))
        let frame = try compositor.renderFrame(sources: [:], time: 0)
        let pixel = PixelBuffers.pixel(in: frame, x: 32, y: 16)
        #expect(pixel.r == 0 && pixel.g == 0 && pixel.b == 0)
    }

    @Test func overlaysDrawOnTopWithTopLeftOrigin() throws {
        let source = try PixelBuffers.makeBuffer(width: 64, height: 32)
        try PixelBuffers.fill(source, red: 1, green: 0, blue: 0)
        let overlay = SolidOverlay(rect: UnitRect(x: 0, y: 0, width: 0.5, height: 0.5), red: 0, green: 0, blue: 1)
        let compositor = try FrameCompositor(plan: plan(videoLayers: [VideoLayer(trackID: 1)], overlays: [overlay]))
        let frame = try compositor.renderFrame(sources: [1: source], time: 0)
        let covered = PixelBuffers.pixel(in: frame, x: 8, y: 4)
        let uncovered = PixelBuffers.pixel(in: frame, x: 56, y: 28)
        #expect(covered.b > 200 && covered.r < 30)
        #expect(uncovered.r > 200 && uncovered.b < 30)
    }

    @Test func timestampOverlayDrawsSomething() throws {
        let compositor = try FrameCompositor(
            plan: RenderPlan(
                outputWidth: 320, outputHeight: 180, frameRate: 30, videoLayers: [], overlays: [TimestampOverlay()]))
        let frame = try compositor.renderFrame(sources: [:], time: 61.5)
        var lit = 0
        for y in 0..<30 {
            for x in 0..<160 where PixelBuffers.pixel(in: frame, x: x, y: y).r > 128 { lit += 1 }
        }
        #expect(lit > 50, "expected white glyph pixels in the top-left corner, found \(lit)")
        let bottomRight = PixelBuffers.pixel(in: frame, x: 300, y: 170)
        #expect(bottomRight.r == 0)
    }

    @Test func timestampFormatting() {
        #expect(TimestampOverlay.format(61.5) == "1:01.50")
        #expect(TimestampOverlay.format(3600) == "1:00:00.00")
        #expect(TimestampOverlay.format(-1) == "0:00.00")
    }

    @Test func pixelBufferDrawUsesTopLeftOriginAndClears() throws {
        let buffer = try PixelBuffers.makeBuffer(width: 8, height: 8)
        try PixelBuffers.draw(into: buffer) { context, _ in
            context.setFillColor(PixelBuffers.color(red: 1, green: 1, blue: 1))
            context.fill(CGRect(x: 0, y: 0, width: 8, height: 2))  // top two rows
        }
        #expect(PixelBuffers.pixel(in: buffer, x: 4, y: 0).a == 255)
        #expect(PixelBuffers.pixel(in: buffer, x: 4, y: 7).a == 0)
    }
}
