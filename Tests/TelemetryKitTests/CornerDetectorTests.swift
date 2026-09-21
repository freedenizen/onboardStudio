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
