import CoreGraphics
import Foundation
import ProjectModel
import TelemetryKit
import Testing

@testable import RenderKit

@Suite("Graph ghost")
struct GraphGhostTests {
    static let session = CoachingTrackSession.session

    static func renderer(_ params: GraphParams, reference: CoachingReference? = .fastestRolling) throws
        -> GraphRenderer
    {
        var track: CoachingTrack?
        if let reference { track = try #require(CoachingTrack.make(session: session, reference: reference)) }
        let context = ObjectContext(
            objectID: DisplayObjectID(), frame: UnitRect(x: 0, y: 0, width: 0.8, height: 0.4), opacity: 1,
            sampler: TelemetrySampler(session: session), sync: .identity, cache: RenderCache(), coaching: track)
        return GraphRenderer(context: context, params: params)
    }

    @Test func theCoachingReferenceIsTheGhostWhenChosen() throws {
        var params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap)
        params.ghost = .coachingReference
        let renderer = try Self.renderer(params)
        let slowLap = Self.session.laps[1]
        let layout = renderer.layout(at: slowLap.start + 10, pointBudget: 200)
        let ghost = try #require(layout.traces.first { $0.isGhost })
        let reference = try #require(renderer.context.coaching?.reference)
        #expect(ghost.points.count == reference.count)
        #expect(abs((ghost.points.last?.x ?? 0) - reference.lengthMeters) < 0.01)
        #expect(ghost.color == params.ghostColor)
        // The ghost's values are the reference's, in the object's display unit.
        let onStraight = try #require(ghost.points.first { $0.x > 60 && $0.x < 100 })
        let expected = renderer.context.units.value(
            try #require(reference.value(of: .speed, atDistance: onStraight.x)), of: "speed")
        #expect(abs(onStraight.y - expected) < 0.01)
        // The live trace is there too, and the axis reaches the whole reference.
        #expect(layout.traces.contains { !$0.isGhost })
        #expect(layout.xRange.upperBound >= reference.lengthMeters)
    }

    @Test func aChannelTheReferenceLacksDrawsNoGhost() throws {
        var params = GraphParams(
            series: [GraphSeries(channel: "speed"), GraphSeries(channel: "obd:coolant")], axis: .lap)
        params.ghost = .coachingReference
        let renderer = try Self.renderer(params)
        let layout = renderer.layout(at: Self.session.laps[1].start + 10, pointBudget: 200)
        #expect(layout.traces.filter(\.isGhost).map(\.seriesIndex) == [0])
    }

    @Test func withoutACoachingTrackOrWithTheDefaultTheBestLapIsTheGhost() throws {
        var params = GraphParams(series: [GraphSeries(channel: "speed")], axis: .lap)
        params.ghost = .coachingReference
        let none = try Self.renderer(params, reference: nil)
        let time = Self.session.laps[1].start + 10
        // No coaching track: the ghost falls back to the best lap, as it always drew.
        #expect(none.layout(at: time, pointBudget: 200).traces.contains { $0.isGhost })
        params.ghost = .bestLap
        let best = try Self.renderer(params)
        let ghost = try #require(best.layout(at: time, pointBudget: 200).traces.first { $0.isGhost })
        #expect(ghost.points.count <= 200)
    }
}
