import Foundation
import Testing

@testable import TelemetryKit

@Suite("Corner detection")
struct CornerDetectorTests {
    static let geometry = SyntheticTrack.geometry()
    static let session = SyntheticTrack.session()

    @Test func findsBothBendsAndNeitherStraight() throws {
        let lap = try #require(Self.session.laps.first)
        let corners = CornerDetector.corners(of: lap, in: Self.session)
        #expect(corners.count == 2)
        // Smoothing spreads a corner a little either side of where the geometry turns, so the
        // test allows the smoothing window rather than demanding the exact metre.
        let tolerance = CornerDetector.Options().smoothingMeters
        #expect(abs(corners[0].startDistance - Self.geometry.firstBend.lowerBound) < tolerance)
        #expect(abs(corners[0].endDistance - Self.geometry.firstBend.upperBound) < tolerance)
        #expect(abs(corners[1].startDistance - Self.geometry.secondBend.lowerBound) < tolerance)
        #expect(abs(corners[1].endDistance - Self.geometry.secondBend.upperBound) < tolerance)
    }

    @Test func measuresTheTurnAndItsDirection() throws {
        let lap = try #require(Self.session.laps.first)
        let corners = CornerDetector.corners(of: lap, in: Self.session)
        for corner in corners {
            #expect(corner.turnsRight)
            #expect(abs(corner.headingChangeDegrees - 180) < 10)
            #expect(
                Self.geometry.firstBend.contains(corner.apexDistance)
                    || Self.geometry.secondBend.contains(corner.apexDistance))
        }
    }

    @Test func aLeftHandCircuitReadsAsLeft() throws {
        // Driving the same shape the other way round makes every bend a left-hander.
        let mirrored = SyntheticTrack.session(mirrored: true)
        let lap = try #require(mirrored.laps.first)
        let corners = CornerDetector.corners(of: lap, in: mirrored)
        #expect(corners.count == 2)
        #expect(corners.allSatisfy { !$0.turnsRight })
    }

    @Test func aCornerOnTheStartFinishLineIsStillOneCorner() throws {
        // Start the lap at the first bend's apex, so that bend is half at the end of the lap and
        // half at the beginning. A detector that works strictly within the lap either misses it
        // (neither half turns far enough) or reports it twice.
        let apex = (Self.geometry.firstBend.lowerBound + Self.geometry.firstBend.upperBound) / 2
        let shifted = SyntheticTrack.session(startOffset: apex)
        let lap = try #require(shifted.laps.first)
        let corners = CornerDetector.corners(of: lap, in: shifted)
        #expect(corners.count == 2)
        #expect(corners.allSatisfy { abs($0.headingChangeDegrees - 180) < 15 })
    }

    @Test func aWrappedCornersDistancesStayInsideTheLap() throws {
        // Found in review: letting the end run past the lap put it in a different coordinate
        // system from the apex, which is what corners are sorted by.
        let apex = (Self.geometry.firstBend.lowerBound + Self.geometry.firstBend.upperBound) / 2
        let shifted = SyntheticTrack.session(startOffset: apex)
        let lap = try #require(shifted.laps.first)
        let corners = CornerDetector.corners(of: lap, in: shifted)
        let wrapped = try #require(corners.first { $0.wrapsStartFinish })
        for distance in [wrapped.startDistance, wrapped.endDistance, wrapped.apexDistance] {
            #expect(distance >= 0)
            #expect(distance < wrapped.lapLengthMeters)
        }
        // And it is still measured as one corner, not as the negative of one.
        #expect(wrapped.lengthMeters > 0)
        #expect(wrapped.lengthMeters < Self.geometry.lapLength / 2)
    }

    @Test func noStraightIsInventedAcrossAWrappedCorner() throws {
        // A gap that runs backwards is not a straight. Siting one there would let
        // SectorMode.cornerAware snap a boundary into the middle of the circuit.
        let apex = (Self.geometry.firstBend.lowerBound + Self.geometry.firstBend.upperBound) / 2
        let shifted = SyntheticTrack.session(startOffset: apex)
        let lap = try #require(shifted.laps.first)
        let corners = CornerDetector.corners(of: lap, in: shifted)
        let lapLength = Self.geometry.lapLength
        for midpoint in CornerDetector.straightMidpoints(between: corners) {
            #expect(midpoint >= 0)
            #expect(midpoint <= lapLength)
            // Every midpoint must be on a straight, which means outside every corner.
            for corner in corners where !corner.wrapsStartFinish {
                #expect(!(midpoint > corner.startDistance && midpoint < corner.endDistance))
            }
        }
    }

    @Test func aWrappedCornerPairsWithTheStraightThatFollowsIt() {
        // The case from review, stated directly. A corner spanning the line ends at 50 m, and the
        // straight after it runs to the next corner at 400 m: its middle is 225.
        //
        // Before the fix the end was stored as 50 + 3000, so this came out as (3050 + 400) / 2 =
        // 1725 — a "straight" in the middle of the circuit, which cornerAware would then snap a
        // sector boundary onto.
        let wrapped = Corner(
            startDistance: 2900, endDistance: 50, apexDistance: 10, headingChangeDegrees: 90,
            lapLengthMeters: 3000)
        let next = Corner(
            startDistance: 400, endDistance: 500, apexDistance: 450, headingChangeDegrees: 90,
            lapLengthMeters: 3000)
        #expect(CornerDetector.straightMidpoints(between: [wrapped, next]) == [225])
        #expect(wrapped.wrapsStartFinish)
        #expect(wrapped.lengthMeters == 150)
        #expect(!next.wrapsStartFinish)
        #expect(next.lengthMeters == 100)
    }

    @Test func aGapThatRunsBackwardsIsNotAStraight() {
        // Whatever ordering produces it, a pair whose first corner ends after the second begins
        // describes no stretch of track, and a midpoint there would be fiction.
        let late = Corner(
            startDistance: 2800, endDistance: 2900, apexDistance: 2850, headingChangeDegrees: 90,
            lapLengthMeters: 3000)
        let early = Corner(
            startDistance: 400, endDistance: 500, apexDistance: 450, headingChangeDegrees: 90,
            lapLengthMeters: 3000)
        #expect(CornerDetector.straightMidpoints(between: [late, early]).isEmpty)
    }

    /// A point-to-point stage that begins in one corner and ends in another turning the same
    /// way: two real corners with a straight between them, and the path does not close.
    static func hillClimb() -> TelemetrySession {
        var east = 0.0
        var north = 0.0
        var heading = 0.0
        var times: [Double] = []
        var latitudes: [Double] = []
        var longitudes: [Double] = []
        var distances: [Double] = []
        let step = 2.0
        let speed = 20.0
        let metresPerDegreeEast = 111_320 * cos(37.5 * .pi / 180)
        // A right-hand bend, then a long straight, then another right-hand bend.
        let turnPerStep = 90.0 / 30.0
        let plan =
            Array(repeating: turnPerStep, count: 30) + Array(repeating: 0.0, count: 150)
            + Array(repeating: turnPerStep, count: 30)
        for (index, turn) in plan.enumerated() {
            times.append(Double(index) * step / speed)
            latitudes.append(37.5 + north / 110_540)
            longitudes.append(-122.0 + east / metresPerDegreeEast)
            distances.append(Double(index) * step)
            heading += turn
            east += sin(heading * .pi / 180) * step
            north += cos(heading * .pi / 180) * step
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .latitude, name: "lat", unit: .degrees, times: times, values: latitudes),
                Channel(role: .longitude, name: "lon", unit: .degrees, times: times, values: longitudes),
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distances),
            ],
            laps: [Lap(number: 1, start: times[0], end: times[times.count - 1], isComplete: true)])
    }

    @Test func anOpenPathNeverJoinsItsFirstAndLastCorners() throws {
        // Found in review: the run-joining was unconditional, so a stage beginning and ending in
        // same-way corners fused them into one impossible corner spanning the whole run.
        let stage = Self.hillClimb()
        let lap = try #require(stage.laps.first)
        let corners = CornerDetector.corners(of: lap, in: stage)
        #expect(corners.count == 2)
        #expect(corners.allSatisfy { !$0.wrapsStartFinish })
        #expect(corners.allSatisfy { $0.turnsRight })
        // And the straight between them survives, which a fused corner would have swallowed.
        #expect(CornerDetector.straightMidpoints(between: corners).count == 1)
    }

    @Test func aStraightLineHasNoCorners() {
        let times = Array(stride(from: 0.0, through: 60.0, by: 0.1))
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(
                    role: .latitude, name: "lat", unit: .degrees, times: times,
                    values: times.map { 37.5 + $0 * 25 / 110_540 }),
                Channel(
                    role: .longitude, name: "lon", unit: .degrees, times: times,
                    values: times.map { _ in -122.0 }),
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: times.map { $0 * 25 }),
            ],
            laps: [Lap(number: 1, start: 0, end: 60, isComplete: true)])
        #expect(CornerDetector.corners(of: session.laps[0], in: session).isEmpty)
    }

    @Test func aSweeperIsOnlyACornerWhenTheRadiusThresholdSaysSo() throws {
        // The bends are 60 m radius; asking only for corners tighter than 20 m finds none.
        let lap = try #require(Self.session.laps.first)
        let options = CornerDetector.Options(cornerRadiusMeters: 20)
        #expect(CornerDetector.corners(of: lap, in: Self.session, options: options).isEmpty)
    }

    @Test func theOnlyStraightBetweenCornersIsTheBackStraight() throws {
        let lap = try #require(Self.session.laps.first)
        let corners = CornerDetector.corners(of: lap, in: Self.session)
        let midpoints = CornerDetector.straightMidpoints(between: corners)
        // Two corners means one gap between them; the pit straight holds the start/finish line
        // and is deliberately not offered.
        #expect(midpoints.count == 1)
        #expect(abs(midpoints[0] - Self.geometry.backStraightMidpoint) < 20)
    }

    @Test func headingDifferenceFoldsAcrossNorth() {
        #expect(abs(CornerDetector.signedDifference(10, 350) - 20) < 1e-9)
        #expect(abs(CornerDetector.signedDifference(350, 10) + 20) < 1e-9)
        #expect(abs(CornerDetector.signedDifference(90, 80) - 10) < 1e-9)
    }
}
