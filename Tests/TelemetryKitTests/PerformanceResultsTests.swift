import Foundation
import Testing

@testable import TelemetryKit

/// What is done with performance runs once measured (#553): the best of each measure, the notes
/// beside an attempt, which sessions are measured on their own, and keeping them in a file.
@Suite struct PerformanceResultsTests {
    typealias Runs = PerformanceRuns

    /// Two launches, the second quicker (5 m/s² against 4), each braked to standing still: the
    /// second at 10 m/s², the first at 8.
    static let twoStarts = Runs.measure(
        in: PerformanceRunsTests.session(phases: [(4, 14), (-8, 7), (0, 3), (5, 13), (-10, 6.5), (0, 2)]))

    @Test func theBestOfEachMeasureIsPicked() throws {
        let result = Self.twoStarts
        #expect(result.attempts.count == 2)
        let launch = try #require(result.best(.zeroToSixtyMph))
        #expect(launch.attempt == 1)
        #expect(abs(launch.seconds - 26.8224 / 5) < 1e-6)
        let quarter = try #require(result.best(.quarterMile))
        #expect(quarter.attempt == 1)
        #expect(
            abs(quarter.seconds - PerformanceRunsTests.timeslip(Runs.DragDistance.quarterMile.metres, accel: 5)) < 0.002
        )
        #expect(quarter.trap != nil)
        let stop = try #require(result.best(.sixtyMph))
        #expect(abs(stop.stop.metres - 26.8224 * 26.8224 / 20) < 0.05, "\(stop.stop.metres)")
        #expect(result.stops[stop.index] == stop.stop)
    }

    @Test func theAttemptAtATimeIsTheOneUnderWay() throws {
        let result = Self.twoStarts
        let second = result.attempts[1]
        #expect(result.attempt(at: (second.start + second.end) / 2) == second)
        #expect(result.attempt(at: second.start - 1) == nil)
        let stop = try #require(result.stops.first)
        #expect(result.stop(at: (stop.start + stop.end) / 2) == stop)
    }

    @Test func aSlopeOrASlowLogIsNotedNotHidden() {
        var attempt = Runs.Attempt(start: 0, end: 10, sampleHertz: 9.9996)
        #expect(attempt.notes.isEmpty, "a 10 Hz log measures a hair under 10 Hz: \(attempt.notes)")
        attempt.slope = -0.018
        attempt.sampleHertz = 5
        #expect(attempt.notes == ["1.8 % downhill: quicker than on the level", "5 Hz: times ±0.1 s"])
        attempt.slope = 0.005
        #expect(attempt.notes == ["5 Hz: times ±0.1 s"], "under 1 % is level enough")
        var stop = Runs.Stop(from: .sixtyMph, start: 0, end: 3, metres: 36)
        stop.slope = -0.02
        #expect(stop.notes == ["2.0 % downhill: longer than on the level"])
        stop.slope = 0.02
        #expect(stop.notes == ["2.0 % uphill: shorter than on the level"])
    }

    @Test func aSessionWithNoLapsIsMeasuredOnItsOwnAndATrackDayOnlyWhenAsked() {
        let lap = Lap(number: 1, start: 0, end: 90, isComplete: true)
        #expect(Runs.isMeasured(asked: nil, laps: []))
        #expect(!Runs.isMeasured(asked: nil, laps: [lap]), "a pit exit is not measured unasked")
        #expect(Runs.isMeasured(asked: true, laps: [lap]))
        #expect(!Runs.isMeasured(asked: false, laps: []))
    }

    @Test func resultsAreKeptAndReadBackAsTheyWere() throws {
        let result = Self.twoStarts
        let data = try JSONEncoder().encode(result)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains("\"zeroToSixtyMph\""), "keyed by measure, readable: \(json.prefix(200))")
        #expect(try JSONDecoder().decode(Runs.Result.self, from: data) == result)
    }
}
