import Foundation
import Testing

@testable import TelemetryKit

@Suite("Lap alignment by position")
struct LapAlignmentTests {
    static let g = SyntheticTrack.geometry()

    /// `session` with its whole trace moved `east` metres: the same lap on a line beside the first.
    static func shifted(_ session: TelemetrySession, east: Double) -> TelemetrySession {
        var moved = session
        guard let longitude = session[.longitude] else { return moved }
        let perDegree = 111_320 * cos(SyntheticTrack.origin.latitude * .pi / 180)
        moved.add(
            Channel(
                role: .longitude, name: longitude.name, unit: longitude.unit, times: longitude.times,
                values: longitude.values.map { $0 + east / perDegree }))
        return moved
    }

    @Test func aLineBesideTheReferenceIsMatchedPlaceForPlace() throws {
        let session = SyntheticTrack.session(laps: 1)
        let beside = Self.shifted(session, east: 3)
        let reference = try #require(LapProfile(lap: session.laps[0], in: session))
        let lap = try #require(LapProfile(lap: beside.laps[0], in: beside))
        let trace = try #require(LapDeltaTrace(lap: lap, reference: reference, alignment: .byPosition))
        #expect(trace.alignment == .byPosition)
        #expect(trace.confidence > 0.85 && trace.confidence <= 1, "\(trace.confidence)")
        // The same lap moved 3 m east: a place on an east–west straight is 3 m further along one
        // line than the other, so the match is within 3 m everywhere and the delta within the
        // 0.12 s that 3 m takes at 25 m/s.
        #expect(trace.delta.allSatisfy { abs($0) < 0.15 })
        for (matched, distance) in zip(trace.lapDistances, trace.distances) {
            #expect(abs(matched - distance) < 3.5, "\(matched) for \(distance)")
        }
        #expect(abs(trace.lapDistance(atReferenceDistance: 100) - 97) < 0.5)
        let back = Self.g.backStraightMidpoint
        #expect(abs(trace.lapDistance(atReferenceDistance: back) - back - 3) < 0.5)
        // Moved east: no offset on the straights that run east and west, 3 m to the left where
        // the car heads south through the first bend, 3 m to the right where it heads north
        // through the second.
        let offsets = try #require(trace.lateralOffset)
        #expect(offsets.count == trace.distances.count)
        #expect(abs(trace.lateralOffset(atDistance: 50) ?? 9) < 0.3)
        #expect(abs(trace.lateralOffset(atDistance: Self.g.backStraightMidpoint) ?? 9) < 0.3)
        let firstApex = (Self.g.firstBend.lowerBound + Self.g.firstBend.upperBound) / 2
        let secondApex = (Self.g.secondBend.lowerBound + Self.g.secondBend.upperBound) / 2
        #expect(abs((trace.lateralOffset(atDistance: firstApex) ?? 0) + 3) < 0.3)
        #expect(abs((trace.lateralOffset(atDistance: secondApex) ?? 0) - 3) < 0.3)
    }

    @Test func aLongerCircuitIsMatchedAtItsOwnCorners() throws {
        // Straights 1 % longer: by distance the second bend's apex is 6 m out, by fraction 6 m
        // out the other way at the first bend; by position each apex meets its own.
        let session = SyntheticTrack.session(laps: 1)
        let longer = SyntheticTrack.session(straight: 404, laps: 1)
        let reference = try #require(LapProfile(lap: session.laps[0], in: session))
        let lap = try #require(LapProfile(lap: longer.laps[0], in: longer))
        let trace = try #require(LapDeltaTrace(lap: lap, reference: reference, alignment: .byPosition))
        #expect(trace.alignment == .byPosition)
        let longerGeometry = SyntheticTrack.geometry(straight: 404)
        let referenceApex = (Self.g.secondBend.lowerBound + Self.g.secondBend.upperBound) / 2
        let lapApex = (longerGeometry.secondBend.lowerBound + longerGeometry.secondBend.upperBound) / 2
        #expect(abs(trace.lapDistance(atReferenceDistance: referenceApex) - lapApex) < 1.5)
        let byDistance = try #require(LapDeltaTrace(lap: lap, reference: reference, alignment: .distance))
        #expect(abs(byDistance.lapDistance(atReferenceDistance: referenceApex) - lapApex) > 4)
        // The longer lap takes longer, and the delta says so at the end.
        #expect(abs(trace.total - (lap.duration - reference.duration)) < 0.1)
        #expect(zip(trace.lapDistances, trace.lapDistances.dropFirst()).allSatisfy { $0 <= $1 })
    }

    @Test func linesTooFarApartFallBackToFractionOfLap() throws {
        let session = SyntheticTrack.session(laps: 1)
        let elsewhere = Self.shifted(session, east: 100)
        let reference = try #require(LapProfile(lap: session.laps[0], in: session))
        let lap = try #require(LapProfile(lap: elsewhere.laps[0], in: elsewhere))
        let trace = try #require(LapDeltaTrace(lap: lap, reference: reference, alignment: .byPosition))
        #expect(trace.alignment == .fractionOfLap)
        #expect(trace.confidence == 0)
        #expect(trace.lateralOffset == nil)
        // A wide line is within tolerance; a generous tolerance accepts the 100 m one too.
        let wide = try #require(
            LapDeltaTrace(lap: lap, reference: reference, alignment: .position(maxResidualMeters: 500)))
        #expect(wide.alignment == .position(maxResidualMeters: 500))
    }

    @Test func withoutPositionsThereIsNothingToMatch() throws {
        let session = ReferenceLapTests.session()
        let lap = try #require(LapProfile(lap: session.laps[0], in: session))
        let reference = try #require(LapProfile(lap: session.laps[1], in: session))
        let trace = try #require(LapDeltaTrace(lap: lap, reference: reference, alignment: .byPosition))
        #expect(trace.alignment == .fractionOfLap)
        #expect(trace.confidence == 0)
        #expect(abs(trace.total - 5) < 0.01)
    }

    @Test func aLapThatBeginsElsewhereOnTheCircuitIsNotMatched() throws {
        let g = Self.g
        let session = SyntheticTrack.session(laps: 1)
        let rotated = SyntheticTrack.session(laps: 1, startOffset: g.lapLength / 2)
        let reference = try #require(LapProfile(lap: session.laps[0], in: session))
        let lap = try #require(LapProfile(lap: rotated.laps[0], in: rotated))
        let trace = try #require(LapDeltaTrace(lap: lap, reference: reference, alignment: .byPosition))
        #expect(trace.alignment == .fractionOfLap)
    }

    @Test func theNearestPointOnAPolylineIsFound() {
        typealias Point = LocalPlane.Point
        // An open three-point line: searches are clamped to it.
        let open = PositionMatcher.Line(
            points: [Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10)], distances: [0, 10, 20], step: 2)
        #expect(!open.isClosed)
        let hit = open.nearest(to: Point(x: 5, y: 3), from: -5, to: 0)
        #expect(hit?.segment == 0)
        #expect(abs((hit?.t ?? 0) - 0.5) < 1e-9)
        #expect(abs((hit?.distance ?? 0) - 3) < 1e-9)
        #expect(abs((hit?.along ?? 0) - 5) < 1e-9)
        let corner = open.nearest(to: Point(x: 12, y: 12), from: 0, to: 9)
        #expect(corner?.segment == 1)
        #expect(corner?.t == 1)
        #expect(open.nearest(to: Point(x: 0, y: 0), from: 2, to: 2) == nil)
        // A closed square: a segment before the start is the end of the lap before.
        let corners = [
            Point(x: 0, y: 0), Point(x: 10, y: 0), Point(x: 10, y: 10), Point(x: 0, y: 10), Point(x: 0, y: 0),
        ]
        let square = PositionMatcher.Line(points: corners, distances: [0, 10, 20, 30, 40], step: 2)
        #expect(square.isClosed)
        let before = square.nearest(to: Point(x: 0, y: 2), from: -1, to: -1)
        #expect(before?.segment == -1)
        #expect(abs((before?.along ?? 0) + 2) < 1e-9)
        let after = square.nearest(to: Point(x: 5, y: 0), from: 4, to: 4)
        #expect(abs((after?.along ?? 0) - 45) < 1e-9)
    }
}
