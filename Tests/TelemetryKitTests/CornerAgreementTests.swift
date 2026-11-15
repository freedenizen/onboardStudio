import Foundation
import Testing

@testable import TelemetryKit

/// #585: a kink some laps find and most do not is not one of the session's corners.
@Suite("Corners the laps agree on")
struct CornerAgreementTests {
    /// The stadium circuit, five laps, with a sidestep on the start straight on the laps `kinked`
    /// names (0-based).
    static func session(kinked: Set<Int>, laps: Int = 5) -> TelemetrySession {
        SyntheticTrack.session(laps: laps, jog: { kinked.contains($0) ? 8 : 0 })
    }

    @Test func theKinkIsACornerOnTheLapsThatDriveIt() throws {
        // The fixture itself: without this the tests below would pass for nothing.
        let session = Self.session(kinked: [0, 2])
        let kinked = CornerDetector.corners(of: session.laps[0], in: session)
        let plain = CornerDetector.corners(of: session.laps[1], in: session)
        #expect(kinked.count == plain.count + 1)
    }

    @Test func aKinkFewLapsFindIsDroppedFromTheReference() throws {
        let session = Self.session(kinked: [0, 2])
        let plain = CornerDetector.corners(of: session.laps[1], in: session)
        let agreed = session.agreedCorners(of: session.laps[0])
        #expect(agreed.count == plain.count)
        // The same corners, not merely as many.
        for (corner, expected) in zip(agreed, plain) {
            #expect(abs(corner.apexDistance - expected.apexDistance) < 20)
        }
    }

    /// Found on a real session: a kink a few metres before a turn is within reach of that turn's
    /// bend, so a lap with only the turn "found" the kink too until each lap's corners were paired
    /// one to one with the reference's, closest first.
    @Test func aKinkJustBeforeATurnIsNotFoundInTheTurn() throws {
        let session = SyntheticTrack.session(laps: 5, jog: { [0, 2].contains($0) ? 8 : 0 }, jogStart: 140, jogSpan: 50)
        let kinked = CornerDetector.corners(of: session.laps[0], in: session)
        let plain = CornerDetector.corners(of: session.laps[1], in: session)
        try #require(kinked.count == plain.count + 1)
        // The case itself: the kink is within reach of the plain lap's first turn.
        let kink = try #require(
            kinked.first { corner in !plain.contains { abs($0.apexDistance - corner.apexDistance) < 20 } })
        let turn = try #require(TurnName(label: "1", corner: plain[0]))
        #expect(try #require(CornerNaming.distance(from: kink, to: turn)) <= CornerNaming.matchRadiusMeters)
        #expect(session.agreedCorners(of: session.laps[0]).count == plain.count)
    }

    @Test func aKinkMostLapsFindIsKept() throws {
        let session = Self.session(kinked: [0, 1, 2, 4])
        let kinked = CornerDetector.corners(of: session.laps[0], in: session)
        #expect(session.agreedCorners(of: session.laps[0]).count == kinked.count)
    }

    @Test func aLapWithoutTheKinkGainsNothing() throws {
        // The other way round is not this fix's: a bend the reference drove straight through has
        // no apex on that lap to measure (see `CornerAgreement`).
        let session = Self.session(kinked: [0, 1, 2, 4])
        let plain = CornerDetector.corners(of: session.laps[3], in: session)
        #expect(session.agreedCorners(of: session.laps[3]).count == plain.count)
    }

    @Test func twoLapsAreNotEnoughToVote() throws {
        let session = Self.session(kinked: [0], laps: 2)
        let kinked = CornerDetector.corners(of: session.laps[0], in: session)
        #expect(session.agreedCorners(of: session.laps[0]).count == kinked.count)
    }

    @Test func aProjectSavedBeforeKeepsEveryCorner() throws {
        var session = Self.session(kinked: [0, 2])
        session.legacyCornersPerLap = true
        let kinked = CornerDetector.corners(of: session.laps[0], in: session)
        #expect(session.agreedCorners(of: session.laps[0]).count == kinked.count)
    }

    @Test func aProfileOfALapIsVotedOnAsTheLapIs() throws {
        let session = Self.session(kinked: [0, 2])
        let profile = try #require(LapProfile(lap: session.laps[0], in: session))
        let plain = CornerDetector.corners(of: session.laps[1], in: session)
        #expect(session.agreedCorners(of: profile).count == plain.count)
    }

    @Test func aCornerWithoutAPositionStays() throws {
        let unplaced = Corner(
            startDistance: 100, endDistance: 140, apexDistance: 120, headingChangeDegrees: 40, lapLengthMeters: 1000)
        let session = Self.session(kinked: [])
        let others = session.laps.map { CornerDetector.corners(of: $0, in: session) }
        #expect(CornerAgreement.agreed([unplaced], by: others) == [unplaced])
    }
}
