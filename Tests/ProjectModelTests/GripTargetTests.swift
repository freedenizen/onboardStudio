import Foundation
import Testing

@testable import ProjectModel
@testable import TelemetryKit

/// #631: what the Analysis view's friction circle reads the laps against.
@Suite("The friction circle's grip target (#631)")
struct GripTargetTests {
    static let limit = CarGripLimit(
        typical: GripEnvelope(circle: 1.0), best: GripEnvelope(circle: 1.2), sessions: 3, basis: ["dry"],
        adjustment: 1)

    @Test func theCarsLimitComesFirst() throws {
        let target = try #require(GripTarget.choose(car: Self.limit, session: GripEnvelope(circle: 0.9)))
        #expect(target.envelope == GripEnvelope(circle: 1.2))
        #expect(target.caption == "Dashed: the car's grip, 1.00–1.20 G from 3 sessions, dry")
        #expect(target.noun == "the car's grip")
    }

    @Test func theDriversAdjustmentMovesTheLine() throws {
        var limit = Self.limit
        limit.adjustment = 1.1
        let target = GripTarget.car(limit)
        #expect(abs(target.envelope.peak - 1.32) < 1e-9)
    }

    @Test func aSessionTheLogbookDoesNotKnowIsReadAgainstItself() throws {
        let target = try #require(GripTarget.choose(car: nil, session: GripEnvelope(circle: 0.9)))
        #expect(target.source == .session)
        #expect(target.caption == "Dashed: the most this session reached")
        #expect(GripTarget.choose(car: nil, session: nil) == nil)
    }

    @Test func theMostUsedIsAShareOfTheLimitInEachPointsDirection() {
        var reach = Array(repeating: 1.0, count: GripEnvelope.directions)
        reach[0] = 1.25  // braking
        let target = GripTarget(envelope: GripEnvelope(reach: reach), source: .session)
        #expect(abs(target.mostUsed([(0, -1.0), (0.5, 0)]) - 0.8) < 1e-9)
        #expect(abs(target.mostUsed([(0.9, 0)]) - 0.9) < 1e-9)
        #expect(target.mostUsed([]) == 0)
    }
}
