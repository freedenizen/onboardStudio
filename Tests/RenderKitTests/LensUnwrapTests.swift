import CoreImage
import CoreVideo
import Foundation
import Testing

@testable import ProjectModel
@testable import RenderKit

/// Synthetic sources with known geometry so the unwrap can be checked by colour.
enum LensSources {
    /// 256×128 equirectangular: north (top) half blue, south half red, a green stripe at
    /// longitude 0 (the centre column) and a yellow stripe at +90° (three quarters across).
    static func equirectangular() throws -> CVPixelBuffer {
        let buffer = try PixelBuffers.makeBuffer(width: 256, height: 128)
        try PixelBuffers.draw(into: buffer) { cg, _ in
            cg.setFillColor(PixelBuffers.color(red: 0, green: 0, blue: 1))
            cg.fill(CGRect(x: 0, y: 0, width: 256, height: 64))
            cg.setFillColor(PixelBuffers.color(red: 1, green: 0, blue: 0))
            cg.fill(CGRect(x: 0, y: 64, width: 256, height: 64))
            cg.setFillColor(PixelBuffers.color(red: 0, green: 1, blue: 0))
            cg.fill(CGRect(x: 122, y: 0, width: 12, height: 128))
            cg.setFillColor(PixelBuffers.color(red: 1, green: 1, blue: 0))
            cg.fill(CGRect(x: 186, y: 0, width: 12, height: 128))
        }
        return buffer
    }

    /// 200×200 fisheye (180° across the width): white inside 45° of the axis, black beyond, with
    /// a green wedge to the right of the centre.
    static func fisheye() throws -> CVPixelBuffer {
        let buffer = try PixelBuffers.makeBuffer(width: 200, height: 200)
        try PixelBuffers.draw(into: buffer) { cg, _ in
            cg.setFillColor(PixelBuffers.color(red: 0, green: 0, blue: 0))
            cg.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
            cg.setFillColor(PixelBuffers.color(red: 1, green: 1, blue: 1))
            cg.fillEllipse(in: CGRect(x: 50, y: 50, width: 100, height: 100))
            cg.setFillColor(PixelBuffers.color(red: 0, green: 1, blue: 0))
            cg.fill(CGRect(x: 120, y: 95, width: 30, height: 10))
        }
        return buffer
    }
}

@Suite("Lens unwrap")
struct LensUnwrapTests {
    /// Renders the unwrap through a Metal-backed context when available and through the software
    /// renderer, so both kernel backends are covered.
    func render(_ settings: LensSettings, source: CVPixelBuffer, software: Bool) throws -> CVPixelBuffer {
        let image = LensUnwrap.apply(settings, to: CIImage(cvPixelBuffer: source))
        let size = LensUnwrap.outputSize(for: settings, sourceSize: CGSize(width: source.width, height: source.height))
        let output = try PixelBuffers.makeBuffer(width: Int(size.width), height: Int(size.height))
        let context = CIContext(options: [.useSoftwareRenderer: software, .cacheIntermediates: false])
        context.render(
            image, to: output, bounds: CGRect(origin: .zero, size: size), colorSpace: PixelBuffers.colorSpace)
        return output
    }

    static let backends = [false, true]

    @Test(arguments: backends) func equirectangularCentreLooksAtLongitudeZero(software: Bool) throws {
        let frame = try render(
            LensSettings(mode: .equirectangular), source: try LensSources.equirectangular(), software: software)
        #expect(frame.width == 128 && frame.height == 72)
        let centre = PixelBuffers.pixel(in: frame, x: 64, y: 36)
        #expect(centre.g > 200 && centre.r < 60, "centre \(centre)")
        let top = PixelBuffers.pixel(in: frame, x: 20, y: 4)
        #expect(top.b > 200 && top.r < 60, "top \(top)")
        let bottom = PixelBuffers.pixel(in: frame, x: 20, y: 68)
        #expect(bottom.r > 200 && bottom.b < 60, "bottom \(bottom)")
        // The yellow stripe at +90° is outside a 90° window.
        for x in stride(from: 2, to: 128, by: 6) {
            let p = PixelBuffers.pixel(in: frame, x: x, y: 36)
            #expect(!(p.r > 200 && p.g > 200), "yellow at x=\(x)")
        }
    }

    @Test(arguments: backends) func yawTurnsRight(software: Bool) throws {
        let frame = try render(
            LensSettings(mode: .equirectangular, yaw: 90), source: try LensSources.equirectangular(),
            software: software)
        let centre = PixelBuffers.pixel(in: frame, x: 64, y: 36)
        #expect(centre.r > 200 && centre.g > 200 && centre.b < 60, "centre \(centre)")
    }

    @Test(arguments: backends) func pitchLooksUp(software: Bool) throws {
        let frame = try render(
            LensSettings(mode: .equirectangular, pitch: 45), source: try LensSources.equirectangular(),
            software: software)
        for y in [4, 36, 68] {
            let p = PixelBuffers.pixel(in: frame, x: 20, y: y)
            #expect(p.b > 200 && p.r < 60, "y=\(y) \(p)")
        }
    }

    @Test(arguments: backends) func fisheyeKeepsTheCentreAndDropsTheCorners(software: Bool) throws {
        let frame = try render(
            LensSettings(mode: .fisheye, fov: 180, outputFov: 90), source: try LensSources.fisheye(),
            software: software)
        #expect(frame.width == 200 && frame.height == 200)
        let centre = PixelBuffers.pixel(in: frame, x: 100, y: 100)
        #expect(centre.r > 200 && centre.g > 200 && centre.b > 200, "centre \(centre)")
        // 45° off axis is the picture's edge; 54.7° (the corners) is outside the white disc.
        let corner = PixelBuffers.pixel(in: frame, x: 4, y: 4)
        #expect(corner.r < 40 && corner.g < 40, "corner \(corner)")
        let inner = PixelBuffers.pixel(in: frame, x: 40, y: 100)
        #expect(inner.r > 200, "inner \(inner)")
        // The green wedge sits to the right of the centre in the source and stays there.
        let right = PixelBuffers.pixel(in: frame, x: 140, y: 100)
        #expect(right.g > 200 && right.r < 60, "right \(right)")
        let left = PixelBuffers.pixel(in: frame, x: 60, y: 100)
        #expect(left.r > 200 && left.g > 200, "left \(left)")
    }

    @Test func backendsAgree() throws {
        let settings = LensSettings(mode: .equirectangular, yaw: 20, pitch: -10, roll: 5)
        let gpu = try render(settings, source: try LensSources.equirectangular(), software: false)
        let cpu = try render(settings, source: try LensSources.equirectangular(), software: true)
        var different = 0
        for y in stride(from: 0, to: 72, by: 3) {
            for x in stride(from: 0, to: 128, by: 3) {
                let a = PixelBuffers.pixel(in: gpu, x: x, y: y)
                let b = PixelBuffers.pixel(in: cpu, x: x, y: y)
                if abs(Int(a.r) - Int(b.r)) > 48 || abs(Int(a.g) - Int(b.g)) > 48 || abs(Int(a.b) - Int(b.b)) > 48 {
                    different += 1
                }
            }
        }
        #expect(different < 40, "\(different) sampled pixels differ")
    }

    @Test func inactiveSettingsReturnTheSource() throws {
        let source = CIImage(cvPixelBuffer: try LensSources.fisheye())
        #expect(LensUnwrap.apply(.none, to: source) === source)
    }

    @Test func unwrapRunsInsideTheVideoLayerPipeline() throws {
        let transform = VideoTransform(lens: LensSettings(mode: .equirectangular, pitch: 45))
        let plan = RenderPlan(
            outputWidth: 128, outputHeight: 72, frameRate: 30,
            videoLayers: [VideoLayer(trackID: 1, transform: transform)], overlays: [])
        let frame = try FrameCompositor(plan: plan).renderFrame(
            sources: [1: try LensSources.equirectangular()], time: 0)
        let p = PixelBuffers.pixel(in: frame, x: 20, y: 60)
        #expect(p.b > 200 && p.r < 60, "\(p)")
        let centre = PixelBuffers.pixel(in: frame, x: 64, y: 36)
        #expect(centre.g > 200, "\(centre)")
        try GoldenImage.assertMatches(frame, named: "lens-equirect-pitch45")
    }
}

extension CVPixelBuffer {
    var width: Int { CVPixelBufferGetWidth(self) }
    var height: Int { CVPixelBufferGetHeight(self) }
}
