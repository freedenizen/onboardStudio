import CoreGraphics
import CoreVideo
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

/// The G-force plot used to read `lateralG`/`longitudinalG` and nothing else, so a logger that
/// reports a left turn as positive — ISO 8855 vehicle axes, which RaceChrono follows — drew every
/// corner mirrored. Each axis now takes its channel and its sign from the object.
@Suite("G-force axes")
struct GForceAxisTests {
    let size = CGSize(width: 400, height: 400)

    /// A steady right-hand corner under braking: +0.8 G lateral, −0.4 G longitudinal. A second
    /// pair of channels carries the same corner under the opposite sign convention.
    var session: TelemetrySession {
        TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .lateralG, name: "lat", unit: .gForce, times: [0, 10], values: [0.8, 0.8]),
                Channel(role: .longitudinalG, name: "long", unit: .gForce, times: [0, 10], values: [-0.4, -0.4]),
                Channel(role: .aux("lat_iso"), name: "lat_iso", unit: .gForce, times: [0, 10], values: [-0.8, -0.8]),
            ])
    }

    func render(_ params: GForceParams) throws -> CVPixelBuffer {
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: UnitRect(x: 0, y: 0, width: 1, height: 1), opacity: 1,
            sampler: TelemetrySampler(session: session), sync: .identity, cache: RenderCache())
        let renderer = try #require(RenderPlanner.renderer(for: .gForce(params), context: context, image: nil))
        let plan = RenderPlan(
            outputWidth: Int(size.width), outputHeight: Int(size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: 5)
    }

    /// Where the bright dot sits, as the centre of mass of the pixels that are clearly the dot
    /// colour. Returns nil when the plot is blank.
    func dot(in buffer: CVPixelBuffer) -> CGPoint? {
        var sumX = 0.0
        var sumY = 0.0
        var count = 0.0
        for y in stride(from: 0, to: Int(size.height), by: 2) {
            for x in stride(from: 0, to: Int(size.width), by: 2) {
                let p = PixelBuffers.pixel(in: buffer, x: x, y: y)
                // The accent dot is the only strongly orange thing on the dark face.
                guard p.r > 180, p.g > 100, p.g < 200, p.b < 90 else { continue }
                sumX += Double(x)
                sumY += Double(y)
                count += 1
            }
        }
        guard count > 4 else { return nil }
        return CGPoint(x: sumX / count, y: sumY / count)
    }

    @Test func defaultsPlotRightAndBackFromTheStandardRoles() throws {
        var params = GForceParams()
        params.trailSeconds = 0
        let point = try #require(dot(in: try render(params)))
        #expect(point.x > size.width / 2 + 20, "a right turn puts the dot right of centre: \(point)")
        #expect(point.y > size.height / 2 + 10, "braking puts it below centre: \(point)")
    }

    @Test func invertingLateralMirrorsTheDotAcrossTheCentre() throws {
        var params = GForceParams()
        params.trailSeconds = 0
        let plain = try #require(dot(in: try render(params)))
        params.invertLateral = true
        let flipped = try #require(dot(in: try render(params)))
        #expect(flipped.x < size.width / 2 - 20, "inverted, the same corner goes left: \(flipped)")
        #expect(abs((plain.x - size.width / 2) + (flipped.x - size.width / 2)) < 4, "mirrored, not moved")
        #expect(abs(plain.y - flipped.y) < 4, "the other axis is untouched")
    }

    @Test func invertingLongitudinalFlipsOnlyTheVerticalAxis() throws {
        var params = GForceParams()
        params.trailSeconds = 0
        let plain = try #require(dot(in: try render(params)))
        params.invertLongitudinal = true
        let flipped = try #require(dot(in: try render(params)))
        #expect(flipped.y < size.height / 2 - 10, "inverted, braking reads as acceleration: \(flipped)")
        #expect(abs(plain.x - flipped.x) < 4, "the lateral axis is untouched")
    }

    /// The point of the feature: bind the axis to the logger's own channel and correct its sign,
    /// and the ISO-convention channel lands exactly where the RaceRender-convention one does.
    @Test func anExplicitChannelOverridesTheStandardRole() throws {
        var params = GForceParams()
        params.trailSeconds = 0
        let standard = try #require(dot(in: try render(params)))

        params.lateralChannel = "aux:lat_iso"
        let uncorrected = try #require(dot(in: try render(params)))
        #expect(uncorrected.x < size.width / 2 - 20, "the ISO channel reads the corner the other way")

        params.invertLateral = true
        let corrected = try #require(dot(in: try render(params)))
        #expect(abs(corrected.x - standard.x) < 4, "corrected, it matches the standard role: \(corrected)")
    }
}
