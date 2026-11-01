import Foundation
import Testing

@testable import TelemetryKit

@Suite("Lap profile")
struct LapProfileTests {
    static func session(channels: [Channel], laps: [Lap]) -> TelemetrySession {
        TelemetrySession(info: SessionInfo(sourceFormat: "test"), channels: channels, laps: laps)
    }

    @Test func aSyntheticLapIsGriddedAndItsPhysicsDerived() throws {
        let g = SyntheticTrack.geometry()
        let session = SyntheticTrack.session(laps: 2)
        let profile = try #require(LapProfile(lap: session.laps[0], in: session))
        #expect(profile.label == "Lap 1")
        #expect(abs(profile.lengthMeters - g.lapLength) < 0.01)
        #expect(abs(profile.duration - g.lapLength / 25) < 1e-6)
        #expect(profile.distances.first == 0)
        #expect(profile.elapsed.first == 0)
        #expect(abs(profile.elapsed(atDistance: g.lapLength / 2) - profile.duration / 2) < 0.05)
        #expect(abs(profile.distance(atElapsed: profile.duration / 4) - g.lapLength / 4) < 1)
        // No speed was recorded, so it comes from the distance channel: a steady 25 m/s.
        #expect(profile.source(of: .speed) == .speedTrace)
        let speed = try #require(profile.value(of: .speed, atDistance: g.backStraightMidpoint))
        #expect(abs(speed - 25) < 0.05)
        // Lateral G: v²/r in a bend, turning right, nothing on a straight.
        #expect(profile.source(of: .lateralG) == .position)
        let apex = (g.firstBend.lowerBound + g.firstBend.upperBound) / 2
        let inBend = try #require(profile.value(of: .lateralG, atDistance: apex))
        #expect(abs(inBend - 25 * 25 / g.radius / LapProfile.gravity) < 0.05, "\(inBend)")
        let onStraight = try #require(profile.value(of: .lateralG, atDistance: g.backStraightMidpoint))
        #expect(abs(onStraight) < 0.02)
        // Steady speed: no longitudinal G anywhere.
        #expect(profile.source(of: .longitudinalG) == .speedTrace)
        let maxLongitudinal = try #require(profile.channels[.longitudinalG]?.map(abs).max())
        #expect(maxLongitudinal < 0.02)
        // Heading runs east along the bottom straight and west along the top one.
        #expect(abs((profile.heading(atDistance: 10) ?? 0) - 90) < 1)
        #expect(abs((profile.heading(atDistance: g.backStraightMidpoint) ?? 0) - 270) < 1)
        #expect(profile.position(atDistance: 0) != nil)
        #expect(!profile.has(.throttle))
        #expect(profile.value(of: .throttle, atDistance: 100) == nil)
    }

    @Test func aMirroredCircuitTurnsLeft() throws {
        let g = SyntheticTrack.geometry()
        let session = SyntheticTrack.session(laps: 1, mirrored: true)
        let profile = try #require(LapProfile(lap: session.laps[0], in: session))
        let apex = (g.firstBend.lowerBound + g.firstBend.upperBound) / 2
        #expect((profile.value(of: .lateralG, atDistance: apex) ?? 0) < -1)
    }

    @Test func brakingShowsAsNegativeLongitudinalG() throws {
        // Full speed on the first half of the lap, half speed on the second: the car slows at halfway.
        let g = SyntheticTrack.geometry()
        let session = SyntheticTrack.session(laps: 1) { _, into in into < g.lapLength / 2 ? 1 : 0.5 }
        let profile = try #require(LapProfile(lap: session.laps[0], in: session))
        let braking = try #require(profile.value(of: .longitudinalG, atDistance: g.lapLength / 2))
        #expect(braking < -0.1, "\(braking)")
        #expect(abs(profile.value(of: .longitudinalG, atDistance: g.lapLength / 4) ?? 1) < 0.02)
    }

    @Test func recordedChannelsAreSampledInCanonicalUnits() throws {
        let times = Array(stride(from: 0.0, through: 10.0, by: 1))
        let session = Self.session(
            channels: [
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: times.map { $0 * 10 }),
                Channel(
                    role: .speed, name: "s", unit: .kilometersPerHour, times: times, values: times.map { _ in 36 }),
                Channel(role: .throttle, name: "t", unit: .percent, times: times, values: times.map { $0 * 10 }),
                Channel(
                    role: .gear, name: "g", unit: .none, times: times, values: times.map { $0 < 5 ? 2 : 3 },
                    interpolation: .step),
            ], laps: [Lap(number: 1, start: 0, end: 10, isComplete: true)])
        let profile = try #require(LapProfile(lap: session.laps[0], in: session, stepMeters: 5))
        #expect(profile.source(of: .speed) == .recorded)
        #expect(abs((profile.value(of: .speed, atDistance: 50) ?? 0) - 10) < 1e-9)  // 36 km/h
        #expect(abs((profile.value(of: .throttle, atDistance: 50) ?? 0) - 50) < 1e-9)
        #expect(profile.value(of: .gear, atDistance: 20) == 2)
        #expect(profile.value(of: .gear, atDistance: 60) == 3)
        // Longitudinal G still comes from the speed trace when no G was recorded; steady, so zero.
        #expect(profile.source(of: .longitudinalG) == .speedTrace)
        #expect(abs(profile.value(of: .longitudinalG, atDistance: 50) ?? 1) < 1e-9)
        // No position: no heading, no lateral G.
        #expect(!profile.hasPosition)
        #expect(!profile.has(.lateralG))
        #expect(profile.heading(atDistance: 50) == nil)
    }

    @Test func windowsThatGoNowhereAreRejected() {
        let session = ReferenceLapTests.session()
        #expect(LapProfile(window: .init(start: 5, end: 5), in: session, label: "x") == nil)
        #expect(LapProfile(window: .init(start: 5, end: 5.1), in: session, label: "x") == nil)
        #expect(LapProfile(lap: session.laps[3], in: session) == nil)  // no end
        let noDistance = Self.session(
            channels: [Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [0, 10], values: [1, 1])],
            laps: session.laps)
        #expect(LapProfile(lap: session.laps[0], in: noDistance) == nil)
    }
}

@Suite("Lap delta trace")
struct LapDeltaTraceTests {
    /// 100 m laps at 10, 20 (the best), 10 and 15 m/s.
    static let session = ReferenceLapTests.session()

    @Test func aSlowerLapFallsBehindMetreForMetre() throws {
        let slow = try #require(LapProfile(lap: Self.session.laps[0], in: Self.session))
        let best = try #require(LapProfile(lap: Self.session.laps[1], in: Self.session))
        let trace = try #require(LapDeltaTrace(lap: slow, reference: best))
        #expect(trace.alignment == .distance)
        #expect(trace.confidence == 1)
        #expect(abs(trace.delta(atDistance: 50) - 2.5) < 0.01)
        #expect(abs(trace.total - 5) < 0.01)
        #expect(abs(trace.loss(from: 25, to: 75) - 2.5) < 0.01)
        #expect(abs((trace.speedDelta(atDistance: 50) ?? 0) + 10) < 0.01)
        // A lap against itself is level all the way round.
        let level = try #require(LapDeltaTrace(lap: best, reference: best))
        #expect(level.delta.allSatisfy { abs($0) < 1e-9 })
        #expect(level.speedDelta?.allSatisfy { abs($0) < 1e-9 } == true)
    }

    @Test func lapsOfDifferentLengthCanBeComparedByFraction() throws {
        // Lap 1: 100 m in 10 s. Lap 2: 110 m in 11 s. Same pace, so by fraction lap 2 is behind by
        // its extra tenth throughout; metre for metre it is level and the reading is not trusted.
        let times = Array(stride(from: 0.0, through: 21.0, by: 0.5))
        let session = LapProfileTests.session(
            channels: [Channel(role: .distance, name: "d", unit: .meters, times: times, values: times.map { $0 * 10 })],
            laps: [
                Lap(number: 1, start: 0, end: 10, isComplete: true),
                Lap(number: 2, start: 10, end: 21, isComplete: true),
            ])
        let short = try #require(LapProfile(lap: session.laps[0], in: session))
        let long = try #require(LapProfile(lap: session.laps[1], in: session))
        let byDistance = try #require(LapDeltaTrace(lap: long, reference: short, alignment: .distance))
        #expect(byDistance.confidence == 0)
        #expect(abs(byDistance.total) < 0.01)
        let byFraction = try #require(LapDeltaTrace(lap: long, reference: short, alignment: .fractionOfLap))
        #expect(abs(byFraction.confidence - 0.5) < 1e-9)
        #expect(abs(byFraction.delta(atDistance: 50) - 0.5) < 0.01)
        #expect(abs(byFraction.total - 1) < 0.01)
        // Speed came from the distance channel on both laps, and it was the same: level.
        #expect(byFraction.speedDelta?.allSatisfy { abs($0) < 0.01 } == true)
    }
}
