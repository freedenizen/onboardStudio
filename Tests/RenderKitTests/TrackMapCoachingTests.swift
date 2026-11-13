import CoreGraphics
import CoreVideo
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

@Suite("Track map coaching options", .gpu)
struct TrackMapCoachingTests {
    static let session = CoachingTrackSession.session
    static let size = CGSize(width: 300, height: 300)

    static func renderer(_ params: TrackMapParams, coaching: Bool = true) throws -> TrackMapRenderer {
        let track = coaching ? CoachingTrack.make(session: session, reference: .sessionBest) : nil
        if coaching { _ = try #require(track) }
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: TelemetrySampler(session: session),
            sync: .identity, cache: RenderCache(), coaching: track)
        return TrackMapRenderer(context: context, params: params)
    }

    /// Lap 2 (the slow lap) while braking for the first corner.
    static func brakingTime() throws -> Double {
        let track = try #require(CoachingTrack.make(session: session, reference: .sessionBest))
        let lap = session.laps[1]
        let analysis = try #require(track.analyses[lap.number])
        return lap.start + analysis.lap.elapsed(atDistance: analysis.corners[0].lap.phaseStart + 30)
    }

    static func frame(_ renderer: TrackMapRenderer, at time: Double) throws -> CVPixelBuffer {
        let plan = RenderPlan(
            outputWidth: Int(size.width), outputHeight: Int(size.height), frameRate: 30, videoLayers: [],
            overlays: [renderer])
        return try FrameCompositor(plan: plan).renderFrame(sources: [:], time: time)
    }

    static func count(in frame: CVPixelBuffer, where match: (Pixel) -> Bool) -> Int {
        var total = 0
        for y in stride(from: 0, to: Int(size.height), by: 2) {
            for x in stride(from: 0, to: Int(size.width), by: 2)
            where match(PixelBuffers.pixel(in: frame, x: x, y: y)) {
                total += 1
            }
        }
        return total
    }

    @Test func offByDefaultTheMapDrawsAsItDid() throws {
        let params = TrackMapParams()
        #expect(!params.usesCoaching)
        let plain = try Self.renderer(params, coaching: false)
        let with = try Self.renderer(params)
        let time = try Self.brakingTime()
        let a = try Self.frame(plain, at: time)
        let b = try Self.frame(with, at: time)
        #expect(Self.count(in: a) { $0.r > 200 } == Self.count(in: b) { $0.r > 200 })
        #expect(with.coachingReading(at: time).lap == nil)
    }

    @Test func theReferenceLineIsDrawnInItsColour() throws {
        var params = TrackMapParams()
        params.lineColor = .white
        params.showReferenceLine = true
        params.referenceLineColor = RGBAColor(red: 0.2, green: 0.6, blue: 1)
        let time = try Self.brakingTime()
        let frame = try Self.frame(try Self.renderer(params), at: time)
        let blue = Self.count(in: frame) { $0.b > 180 && $0.r < 120 }
        #expect(blue > 20, "no reference line: \(blue) blue pixels")
        params.showReferenceLine = false
        let without = try Self.frame(try Self.renderer(params), at: time)
        #expect(Self.count(in: without) { $0.b > 180 && $0.r < 120 } == 0)
    }

    @Test func theSlowLapIsPaintedWhereItLost() throws {
        var params = TrackMapParams()
        params.colorByDelta = true
        params.lossColor = RGBAColor(red: 1, green: 0, blue: 0)
        params.gainColor = RGBAColor(red: 0, green: 1, blue: 0)
        let renderer = try Self.renderer(params)
        let slow = try Self.frame(renderer, at: try Self.brakingTime())
        #expect(Self.count(in: slow) { $0.r > 200 && $0.g < 80 } > 10, "the slow lap shows no loss")
        // The best lap against itself is level everywhere: nothing painted.
        let best = Self.session.laps[3]
        let level = try Self.frame(renderer, at: best.start + 5)
        #expect(Self.count(in: level) { $0.r > 200 && $0.g < 80 } == 0)
        #expect(Self.count(in: level) { $0.g > 200 && $0.r < 80 } == 0)
        // The runs themselves: losses on the slow lap, none on the best.
        let track = try #require(CoachingTrack.make(session: Self.session, reference: .sessionBest))
        #expect(TrackMapRenderer.deltaRuns(of: try #require(track.analyses[2])).contains { $0.isLoss })
        #expect(TrackMapRenderer.deltaRuns(of: try #require(track.analyses[4])).isEmpty)
    }

    @Test func brakeMarksLandOnTheMap() throws {
        var params = TrackMapParams()
        params.showBrakeMarks = true
        params.lineColor = RGBAColor(red: 1, green: 1, blue: 0)
        params.referenceLineColor = RGBAColor(red: 0, green: 1, blue: 1)
        let time = try Self.brakingTime()
        let frame = try Self.frame(try Self.renderer(params), at: time)
        // Yellow marks for the lap, cyan for the reference, each a filled shape bigger than the line.
        #expect(Self.count(in: frame) { $0.r > 200 && $0.g > 200 && $0.b < 80 } > 8)
        #expect(Self.count(in: frame) { $0.g > 200 && $0.b > 200 && $0.r < 80 } > 8)
    }

    @Test func everyOtherLapsLineIsDrawnFaintWithTheQuickestBrighter() throws {
        var params = TrackMapParams()
        params.lineColor = .white
        params.showLineSpread = true
        params.spreadColor = RGBAColor(red: 1, green: 0, blue: 1, alpha: 0.4)
        let time = try Self.brakingTime()
        let frame = try Self.frame(try Self.renderer(params), at: time)
        // Magenta where the other laps run: the quickest at full strength. The fixture's laps all
        // take the same line, so the faint ones lie under it and under the white outline.
        let strong = Self.count(in: frame) { $0.r > 200 && $0.b > 200 && $0.g < 60 }
        #expect(strong > 20, "the quickest other lap at full strength")
        params.showLineSpread = false
        let plain = try Self.frame(try Self.renderer(params), at: time)
        #expect(Self.count(in: plain) { $0.r > 60 && $0.b > 60 && $0.g < 60 } == 0)
    }

    @Test func followingFramesTheCornerAndLetsGoOnTheStraight() throws {
        var params = TrackMapParams()
        params.followCorner = true
        let renderer = try Self.renderer(params)
        let whole = try #require(renderer.projection)
        let braking = renderer.coachingReading(at: try Self.brakingTime())
        let zoomed = try #require(braking.projection)
        #expect(braking.corner?.index == 0)
        #expect(zoomed.maxX - zoomed.minX < (whole.maxX - whole.minX) * 0.7)
        #expect(braking.cacheSuffix == "lap2|corner0")
        // On the back straight the whole circuit is drawn again.
        let track = try #require(CoachingTrack.make(session: Self.session, reference: .sessionBest))
        let lap = Self.session.laps[1]
        let straight = lap.start + (try #require(track.analyses[2])).lap.elapsed(atDistance: 490)
        let open = renderer.coachingReading(at: straight)
        #expect(open.projection == nil)
        #expect(open.corner == nil)
        #expect(open.cacheSuffix == "lap2")
        // A frame renders either way.
        _ = try Self.frame(renderer, at: try Self.brakingTime())
        _ = try Self.frame(renderer, at: straight)
    }
}
