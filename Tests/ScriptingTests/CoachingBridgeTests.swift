import CoreGraphics
import Foundation
import Testing

@testable import Importers
@testable import ProjectModel
@testable import RenderKit
@testable import Scripting
@testable import TelemetryKit

/// `data.reference`, `data.corners` and `data.coaching` on the fixture laps.
@Suite("Scripting coaching bridge")
struct CoachingBridgeTests {
    static let session: TelemetrySession = {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/coaching-laps.csv")
        let importer = RaceRenderCSVImporter()
        guard let session = try? importer.importSession(at: url, options: SessionBuilder.Options()) else {
            return TelemetrySession(info: SessionInfo(sourceFormat: "none"), channels: [])
        }
        return session
    }()

    /// An engine with `data` bound at `time`, with or without the coaching track.
    func bound(at time: Double, coaching: Bool) throws -> ScriptEngine {
        let session = Self.session
        let track = coaching ? try #require(CoachingTrack.make(session: session, reference: .sessionBest)) : nil
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: .full, opacity: 1, sampler: TelemetrySampler(session: session),
            sync: .identity, cache: RenderCache(), coaching: track)
        let engine = ScriptEngine(source: "function frame(c, d) {}")
        let cg = try #require(
            CGContext(
                data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 0, space: PixelBuffers.colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue))
        engine.drawFrame(into: cg, size: CGSize(width: 10, height: 10), time: time, objectContext: context)
        return engine
    }

    /// A moment inside the first corner of the second lap.
    func insideFirstCorner() throws -> Double {
        let session = Self.session
        let track = try #require(CoachingTrack.make(session: session, reference: .sessionBest))
        let lap = session.laps[1]
        let analysis = try #require(track.analyses[lap.number])
        let corner = analysis.corners[0].lap
        return lap.start + analysis.lap.elapsed(atDistance: (corner.phaseStart + corner.corner.apexDistance) / 2)
    }

    /// A moment on the straight between the two corners of the second lap, past the hold and
    /// before the lead of the next brake point.
    func onTheStraight() throws -> Double {
        let session = Self.session
        let track = try #require(CoachingTrack.make(session: session, reference: .sessionBest))
        let lap = session.laps[1]
        let analysis = try #require(track.analyses[lap.number])
        return lap.start + analysis.lap.elapsed(atDistance: 490)
    }

    @Test func theReferenceAndItsCornersAreExposed() throws {
        let engine = try bound(at: insideFirstCorner(), coaching: true)
        #expect(engine.evaluate("data.reference.label.startsWith('Lap ')") == "true")
        #expect(engine.evaluate("data.reference.phrase") == "your best lap")
        #expect(engine.evaluate("data.reference.length > 1000") == "true")
        #expect(engine.evaluate("data.corners.length") == "2")
        #expect(engine.evaluate("data.corners[0].label") == "1")
        #expect(engine.evaluate("data.corners[1].index") == "1")
        #expect(engine.evaluate("data.corners[0].start < data.corners[0].apex") == "true")
        #expect(engine.evaluate("data.corners[0].apex < data.corners[0].end") == "true")
        #expect(engine.evaluate("data.corners[0].end < data.corners[1].start") == "true")
    }

    @Test func theCornerInPlayCarriesTheComparisonAndTheNote() throws {
        let engine = try bound(at: insideFirstCorner(), coaching: true)
        #expect(engine.evaluate("data.coaching.label") == "1")
        #expect(engine.evaluate("data.coaching.lapNumber") == "2")
        #expect(engine.evaluate("data.coaching.held") == "false")
        #expect(engine.evaluate("['braking','entry','apex','exit'].includes(data.coaching.phase)") == "true")
        #expect(engine.evaluate("typeof data.coaching.timeLost") == "number")
        #expect(engine.evaluate("Object.keys(data.coaching.phaseLoss).length") == "4")
        #expect(engine.evaluate("data.coaching.lap.minimumSpeed < data.coaching.reference.minimumSpeed") == "true")
        #expect(engine.evaluate("data.coaching.lap.brakePoint > data.coaching.reference.brakePoint") == "true")
        #expect(engine.evaluate("data.coaching.lap.brakeSource") == "brakeChannel")
        #expect(engine.evaluate("data.coaching.headline.startsWith('Turn 1:')") == "true")
        #expect(engine.evaluate("data.coaching.evidence.length > 0") == "true")
        #expect(engine.evaluate("typeof data.coaching.suggestion") == "string")
    }

    @Test func withoutCoachingEverythingIsEmpty() throws {
        let engine = try bound(at: insideFirstCorner(), coaching: false)
        #expect(engine.evaluate("Object.keys(data.reference).length") == "0")
        #expect(engine.evaluate("data.corners.length") == "0")
        #expect(engine.evaluate("data.coaching") == "null")
        // On a straight, with coaching, there is no corner in play either.
        let straight = try bound(at: onTheStraight(), coaching: true)
        #expect(straight.evaluate("data.coaching") == "null")
        #expect(straight.evaluate("data.corners.length") == "2")
    }
}
