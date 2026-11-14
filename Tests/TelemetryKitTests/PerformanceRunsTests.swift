import Foundation
import Testing

@testable import TelemetryKit

/// Standing starts and stops (#553), checked against arithmetic: at a constant acceleration *a*
/// from rest, speed *v* comes after *v / a* and distance *d* after √(2d / a).
@Suite struct PerformanceRunsTests {
    typealias Runs = PerformanceRuns

    /// A drive in phases of constant acceleration, sampled at `hertz`, standing still at first.
    /// `climb` is height gained per metre driven.
    static func session(
        hertz: Double = 10, standing: Double = 2, phases: [(accel: Double, seconds: Double)], climb: Double = 0
    ) -> TelemetrySession {
        var times: [Double] = []
        var speeds: [Double] = []
        var distances: [Double] = []
        var heights: [Double] = []
        let dt = 1 / hertz
        let total = standing + phases.reduce(0) { $0 + $1.seconds }
        var t = 0.0
        while t <= total + 1e-9 {
            var v = 0.0
            var d = 0.0
            var clock = standing
            for phase in phases where t > clock {
                let span = min(t, clock + phase.seconds) - clock
                d += v * span + phase.accel * span * span / 2
                v = max(0, v + phase.accel * span)
                clock += phase.seconds
            }
            times.append(t)
            speeds.append(v)
            distances.append(d)
            heights.append(100 + climb * d)
            t += dt
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "synthetic"),
            channels: [
                Channel(role: .speed, name: "v", unit: .metersPerSecond, times: times, values: speeds),
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distances),
                Channel(role: .altitude, name: "h", unit: .meters, times: times, values: heights),
            ])
    }

    /// Seconds from rest to `distance` at `accel`, with the 1-ft rollout, as a timeslip reads it.
    static func timeslip(_ distance: Double, accel: Double) -> Double {
        let rollout = 0.3048
        return (2 * (rollout + distance) / accel).squareRoot() - (2 * rollout / accel).squareRoot()
    }

    @Test func aLaunchIsTimedAsAMeterTimesIt() throws {
        // 5 m/s² for 30 s: 150 m/s, past every mark and speed.
        let result = Runs.measure(in: Self.session(phases: [(5, 30)]))
        let attempt = try #require(result.attempts.first)
        #expect(result.attempts.count == 1)
        #expect(abs(attempt.start - 2) < 1e-6, "time zero where the car began to move")
        // Speed times: no rollout.
        #expect(abs(try #require(attempt.speedTimes[.zeroToSixtyMph]) - 26.8224 / 5) < 1e-6)
        #expect(abs(try #require(attempt.speedTimes[.zeroToHundredKmh]) - 27.7778 / 5) < 1e-4)
        let rolling = try #require(attempt.speedTimes[.sixtyToHundredThirtyMph])
        #expect(abs(rolling - 70 * 0.44704 / 5) < 1e-6)
        // Distance times: the 1-ft rollout.
        for mark in Runs.DragDistance.allCases {
            let measured = try #require(attempt.distanceTimes[mark], "\(mark)")
            #expect(abs(measured - Self.timeslip(mark.metres, accel: 5)) < 0.002, "\(mark): \(measured)")
        }
        // Trap: the mean over the last 66 ft before the mark.
        let quarter = DragDistance.quarterMile.metres + 0.3048
        let entered = (2 * (quarter - 66 * 0.3048) / 5).squareRoot()
        let crossed = (2 * quarter / 5).squareRoot()
        let trap = try #require(attempt.trapSpeeds[.quarterMile])
        #expect(abs(trap - 66 * 0.3048 / (crossed - entered)) < 0.05)
        #expect(attempt.slope == 0)
        #expect(attempt.sampleHertz > 9.9)
    }

    typealias DragDistance = PerformanceRuns.DragDistance

    @Test func theRolloutMakesAQuarterMileQuickerThanFromTheFirstMovement() throws {
        let attempt = try #require(Runs.measure(in: Self.session(phases: [(5, 30)])).attempts.first)
        let fromMoving = (2 * DragDistance.quarterMile.metres / 5).squareRoot()
        let saved = fromMoving - (try #require(attempt.distanceTimes[.quarterMile]))
        #expect(saved > 0.2 && saved < 0.4, "\(saved) s")
    }

    @Test func aOneHertzLogIsInterpolatedNotRounded() throws {
        let attempt = try #require(Runs.measure(in: Self.session(hertz: 1, phases: [(5, 30)])).attempts.first)
        #expect(abs(try #require(attempt.speedTimes[.zeroToSixtyMph]) - 26.8224 / 5) < 1e-6)
        #expect(abs(try #require(attempt.distanceTimes[.quarterMile]) - Self.timeslip(402.336, accel: 5)) < 0.06)
        #expect(attempt.sampleHertz < 1.1)
    }

    @Test func aLiftEndsTheAttemptAndLeavesWhatItReached() throws {
        // 5 m/s² to 20 m/s (about 45 mph), then off the throttle.
        let result = Runs.measure(in: Self.session(phases: [(5, 4), (-2, 4)]))
        let attempt = try #require(result.attempts.first)
        #expect(attempt.speedTimes[.zeroToThirtyMph] != nil)
        #expect(attempt.speedTimes[.zeroToSixtyMph] == nil, "it never reached 60")
        #expect(attempt.distanceTimes[.quarterMile] == nil)
    }

    @Test func aStopIsItsDistanceAndTime() throws {
        // Up to 30 m/s, then 9 m/s² to a standstill.
        let result = Runs.measure(in: Self.session(phases: [(5, 6), (0, 3), (-9, 30 / 9.0), (0, 2)]))
        let sixty = try #require(result.stops.first { $0.from == .sixtyMph })
        let v = 26.8224
        #expect(abs(sixty.metres - v * v / 18) < 0.05, "\(sixty.metres) m")
        #expect(abs(sixty.seconds - v / 9) < 0.01, "\(sixty.seconds) s")
        let hundred = try #require(result.stops.first { $0.from == .hundredKmh })
        #expect(abs(hundred.metres - 27.7778 * 27.7778 / 18) < 0.05)
    }

    @Test func aSlopeIsMeasured() throws {
        let attempt = try #require(Runs.measure(in: Self.session(phases: [(5, 20)], climb: -0.02)).attempts.first)
        #expect(abs(try #require(attempt.slope) - -0.02) < 1e-6, "2 % downhill")
    }

    @Test func standingStillIsNoAttempt() {
        #expect(Runs.measure(in: Self.session(phases: [(0, 5)])).attempts.isEmpty)
    }
}
