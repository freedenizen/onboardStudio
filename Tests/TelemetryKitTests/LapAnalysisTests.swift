import Foundation
import Testing

@testable import TelemetryKit

/// #556: laps laid over each other by the place on the track.
@Suite("Laps as data (#556)")
struct LapAnalysisTests {
    static let session = CoachingFixture.session(drivings: [.init(), CoachingFixture.slow, .init()], pedals: true)

    static func analysis(_ numbers: [Int] = [1, 2]) throws -> LapAnalysis {
        let laps = numbers.compactMap { number in session.laps.first { $0.number == number } }
        let profiles = laps.compactMap { lap in LapProfile(lap: lap, in: session).map { ("Lap \(lap.number)", $0) } }
        let reference = try #require(laps.first)
        return try #require(
            LapAnalysis(profiles: profiles, corners: LapAnalysis.corners(of: reference, in: session)))
    }

    @Test func theDeltaStartsAtNothingAndEndsAtTheDifferenceInLapTime() throws {
        let analysis = try Self.analysis()
        let slow = analysis.traces[1]
        let line = analysis.delta(slow, at: analysis.grid())
        #expect(abs(line.first?.value ?? 1) < 0.01)
        let difference = slow.lapTime - analysis.reference.lapTime
        #expect(difference > 0.1, "the slow lap is slower")
        #expect(abs((line.last?.value ?? 0) - difference) < 0.05)
        #expect(analysis.delta(analysis.reference, at: analysis.grid()).allSatisfy { abs($0.value) < 1e-9 })
    }

    @Test func theSlowLapLosesTimeInTheBends() throws {
        let analysis = try Self.analysis()
        let corner = try #require(analysis.corners.first)
        let zoom = analysis.zoom(to: corner)
        let line = analysis.delta(analysis.traces[1], at: analysis.grid(in: zoom, points: 50))
        #expect((line.last?.value ?? 0) > (line.first?.value ?? 0), "time lost through the corner")
        #expect(zoom.lowerBound < corner.range.lowerBound && zoom.upperBound > corner.range.upperBound)
        #expect(analysis.corner(at: corner.apex)?.label == corner.label)
        #expect(analysis.corner(at: analysis.length / 2 + 2_000) == nil)
    }

    @Test func eachLapReadsItsOwnChannelsAtThePlace() throws {
        let analysis = try Self.analysis()
        let apex = try #require(analysis.corners.first).apex
        let readings = analysis.readings(at: apex, roles: [.speed, .brake])
        #expect(readings.count == 2)
        #expect(readings[0].values[.speed] != nil && readings[1].values[.speed] != nil)
        // The slow lap over-slows, its slowest point after the apex.
        let corner = try #require(analysis.corners.first)
        let span = analysis.grid(in: analysis.zoom(to: corner), points: 200)
        let fastest = analysis.values(of: .speed, analysis.traces[0], at: span).map(\.value).min() ?? 0
        let slowest = analysis.values(of: .speed, analysis.traces[1], at: span).map(\.value).min() ?? 0
        #expect(fastest > slowest + 1)
        #expect(readings[0].delta == 0 && readings[1].delta > 0)
        #expect(analysis.values(of: .throttle, analysis.reference, at: analysis.grid(points: 20)).count == 20)
    }

    @Test func theFrictionCircleHasAPointWhereverBothGsAre() throws {
        let analysis = try Self.analysis()
        let points = analysis.frictionCircle(analysis.reference, at: analysis.grid(points: 100))
        #expect(points.count > 90)
        #expect(points.contains { $0.longitudinal < -0.2 }, "braking")
        #expect(points.contains { abs($0.lateral) > 0.2 }, "turning")
    }

    @Test func aClickOnTheMapIsThePlaceNearestIt() throws {
        let analysis = try Self.analysis()
        let place = analysis.length / 3
        let position = try #require(analysis.position(analysis.reference, at: place))
        let found = try #require(analysis.distance(nearestLatitude: position.latitude, longitude: position.longitude))
        #expect(abs(found - place) < analysis.length / 400 + 2)
    }

    @Test func noMoreThanFourLaps() throws {
        let lap = try #require(Self.session.laps.first)
        let profile = try #require(LapProfile(lap: lap, in: Self.session))
        let analysis = try #require(LapAnalysis(profiles: Array(repeating: ("Lap 1", profile), count: 6)))
        #expect(analysis.traces.count == LapAnalysis.maximumLaps)
        #expect(LapAnalysis(profiles: []) == nil)
    }

    @Test func aLongerLapIsStretchedToTheReference() throws {
        let analysis = try Self.analysis()
        for trace in analysis.traces {
            #expect(abs(trace.distance(atReference: analysis.length) - (trace.profile.distances.last ?? 0)) < 1e-6)
        }
    }

    @Test func theSessionTimeAtAPlaceIsWhereTheVideoIs() throws {
        let analysis = try Self.analysis([2, 1])
        let lap2 = try #require(Self.session.laps.first { $0.number == 2 })
        #expect(abs(analysis.sessionTime(analysis.reference, at: 0) - lap2.start) < 0.05)
    }
}
