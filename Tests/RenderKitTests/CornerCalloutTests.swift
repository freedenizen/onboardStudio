import CoreGraphics
import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

@Suite("Corner callout", .gpu)
struct CornerCalloutTests {
    /// The coaching fixture's session (four laps: fast, slow, fast, fast), as the planner hands it over.
    static let session = CoachingTrackSession.session

    static func renderer(
        _ params: CornerCalloutParams = CornerCalloutParams(), speedUnit: SpeedDisplayUnit = .kph,
        frame: UnitRect = UnitRect(x: 0.05, y: 0.1, width: 0.6, height: 0.5)
    ) throws -> CornerCalloutRenderer {
        let track = try #require(CoachingTrack.make(session: session, reference: .sessionBest))
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: frame, opacity: 1, sampler: TelemetrySampler(session: session),
            sync: .identity, cache: RenderCache(), speedUnit: speedUnit, coaching: track)
        return CornerCalloutRenderer(context: context, params: params)
    }

    static func brakeTime(of corner: Int, lap lapIndex: Int) throws -> Double {
        let track = try #require(CoachingTrack.make(session: session, reference: .sessionBest))
        let lap = session.laps[lapIndex]
        let analysis = try #require(track.analyses[lap.number])
        return lap.start + analysis.lap.elapsed(atDistance: analysis.corners[corner].lap.phaseStart)
    }

    /// A moment on the back straight: past the first corner's hold, before the second's lead.
    static func straightTime(lap lapIndex: Int) throws -> Double {
        let track = try #require(CoachingTrack.make(session: session, reference: .sessionBest))
        let lap = session.laps[lapIndex]
        let analysis = try #require(track.analyses[lap.number])
        return lap.start + analysis.lap.elapsed(atDistance: 490)
    }

    @Test func theCardSaysWhatTheCoachingWindowSays() throws {
        let renderer = try Self.renderer()
        // The slow lap's first corner, while braking.
        let card = try #require(renderer.card(at: try Self.brakeTime(of: 0, lap: 1) + 1))
        #expect(card.headline.hasPrefix("Turn 1: "))
        #expect(card.headline.contains(" lost on "))
        #expect(card.timeLost > 0.3)
        #expect(card.evidence.contains { $0.hasPrefix("Braked ") && $0.contains("earlier than your best lap") })
        #expect(card.suggestion?.hasPrefix("Try ") == true)
        // On the straight long before the corner: nothing.
        #expect(renderer.card(at: try Self.straightTime(lap: 1)) == nil)
        // A fast lap's corner against the best (another fast lap): level, no suggestion.
        let level = try #require(renderer.card(at: try Self.brakeTime(of: 0, lap: 2) + 1))
        #expect(level.headline.contains("level with") || level.headline.contains("gained") || level.timeLost < 0.1)
        // Only-opportunities hides it.
        var strict = CornerCalloutParams()
        strict.onlyOpportunities = true
        #expect(try Self.renderer(strict).card(at: try Self.brakeTime(of: 0, lap: 2) + 1) == nil)
        // Imperial when the object draws mph.
        let mph = try Self.renderer(speedUnit: .mph)
        let imperial = try #require(mph.card(at: try Self.brakeTime(of: 0, lap: 1) + 1))
        #expect(imperial.evidence.contains { $0.contains(" ft ") })
    }

    @Test func linesFitTheCardAndWrap() throws {
        let style: (TextDrawing.Style) -> TextDrawing.Style = { $0 }
        let narrow = CGRect(x: 0, y: 0, width: 160, height: 300)
        let lines = CornerCalloutRenderer.layout(
            CornerCalloutRenderer.example, in: narrow, params: CornerCalloutParams(), styled: style)
        #expect(lines.count > 4, "the evidence and suggestion wrap on a narrow card")
        for line in lines {
            let width = TextDrawing.size(of: line.text, style: line.style).width
            #expect(width <= narrow.width + 1, Comment(rawValue: line.text))
        }
        #expect(zip(lines, lines.dropFirst()).allSatisfy { $0.y < $1.y })
        // The headline shrinks rather than overflows.
        let tiny = CGRect(x: 0, y: 0, width: 80, height: 60)
        let small = CornerCalloutRenderer.layout(
            CornerCalloutRenderer.example, in: tiny, params: CornerCalloutParams(), styled: style)
        let first = try #require(small.first)
        #expect(TextDrawing.size(of: first.text, style: first.style).width <= tiny.width + 1)
    }

    @Test func theCardRendersAndIsBlankOnTheStraight() throws {
        let renderer = try Self.renderer()
        let plan = RenderPlan(
            outputWidth: 640, outputHeight: 360, frameRate: 30, videoLayers: [], overlays: [renderer])
        let compositor = try FrameCompositor(plan: plan)
        let braking = try compositor.renderFrame(sources: [:], time: try Self.brakeTime(of: 0, lap: 1) + 1)
        try GoldenImage.assertMatches(braking, named: "corner-callout-turn1")
        let straight = try compositor.renderFrame(sources: [:], time: try Self.straightTime(lap: 1))
        var lit = 0
        for y in stride(from: 40, to: 210, by: 4) {
            for x in stride(from: 40, to: 400, by: 4) where PixelBuffers.pixel(in: straight, x: x, y: y).r > 20 {
                lit += 1
            }
        }
        #expect(lit == 0, "the card drew on the straight")
    }

    @Test func aTemplateWithNoSessionShowsAnExample() throws {
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: UnitRect(x: 0, y: 0, width: 1, height: 1), opacity: 1, sampler: nil,
            sync: .identity, cache: RenderCache())
        let renderer = CornerCalloutRenderer(context: context, params: CornerCalloutParams())
        let plan = RenderPlan(
            outputWidth: 320, outputHeight: 200, frameRate: 30, videoLayers: [], overlays: [renderer])
        let frame = try FrameCompositor(plan: plan).renderFrame(sources: [:], time: 0)
        var lit = 0
        for y in stride(from: 0, to: 200, by: 2) {
            for x in stride(from: 0, to: 320, by: 2) where PixelBuffers.pixel(in: frame, x: x, y: y).r > 60 {
                lit += 1
            }
        }
        #expect(lit > 20)
    }
}

/// `Tests/Fixtures/coaching-laps.csv` read the way the app reads it.
enum CoachingTrackSession {
    static let session: TelemetrySession = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/coaching-laps.csv")
        let importer = RaceRenderCSVImporter()
        guard let session = try? importer.importSession(at: url, options: SessionBuilder.Options()) else {
            return TelemetrySession(info: SessionInfo(sourceFormat: "none"), channels: [])
        }
        return session
    }()
}
