import Foundation
import Testing

@testable import TelemetryKit

@Suite("Lap comparison")
struct LapComparisonTests {
    /// Lap 0 (0–5 s) at 10 m/s, lap 1 (5–10 s) at 5 m/s: the second lap loses time steadily.
    static let session: TelemetrySession = {
        let times = Array(stride(from: 0.0, through: 10.0, by: 0.5))
        let distance = times.map { t in t < 5 ? 10 * t : 50 + 5 * (t - 5) }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .distance, name: "d", unit: .meters, times: times, values: distance)],
            laps: [
                Lap(number: 0, start: 0, end: 5, isComplete: true),
                Lap(number: 1, start: 5, end: nil, isComplete: false),
            ])
    }()

    @Test func timeAtDistanceInterpolates() throws {
        let channel = try #require(Self.session[.distance])
        #expect(LapComparison.time(atDistance: 25, in: channel, between: 0, and: 5) == 2.5)
        #expect(abs((LapComparison.time(atDistance: 12.5, in: channel, between: 0, and: 5) ?? 0) - 1.25) < 1e-9)
        #expect(LapComparison.time(atDistance: 60, in: channel, between: 0, and: 5) == nil)  // beyond lap 0
        #expect(LapComparison.time(atDistance: 60, in: channel, between: 5, and: 10) == 7)
    }

    @Test func deltaGrowsOnTheSlowerLap() {
        // At 7 s the car is 10 m into lap 1; the best lap covered 10 m in 1 s, so it is 1 s behind.
        #expect(abs((LapComparison.deltaToBest(at: 7, session: Self.session) ?? 0) - 1) < 1e-9)
        #expect(abs((LapComparison.deltaToBest(at: 9, session: Self.session) ?? 0) - 2) < 1e-9)
        // During the best lap itself there is no completed lap to compare with.
        #expect(LapComparison.deltaToBest(at: 3, session: Self.session) == nil)
    }

    @Test func deltaNeedsDistance() {
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [0, 10], values: [1, 1])],
            laps: Self.session.laps)
        #expect(LapComparison.deltaToBest(at: 7, session: session) == nil)
    }

    @Test func lapLength() throws {
        let channel = try #require(Self.session[.distance])
        #expect(LapComparison.length(of: Self.session.laps[0], distance: channel) == 50)
        #expect(LapComparison.length(of: Self.session.laps[1], distance: channel) == nil)
    }

    @Test func timeStrings() {
        #expect(TimeParsing.lapTimeString(83.456, decimals: 1) == "1:23.5")
        #expect(TimeParsing.lapTimeString(83.456, decimals: 3) == "1:23.456")
        #expect(TimeParsing.lapTimeString(3725.5, decimals: 2) == "1:02:05.50")
        #expect(TimeParsing.lapTimeString(5, decimals: 0) == "0:05")
        #expect(TimeParsing.deltaString(1.234, decimals: 2) == "+1.23")
        #expect(TimeParsing.deltaString(-0.4, decimals: 2) == "−0.40")
        #expect(TimeParsing.deltaString(-0.001, decimals: 2) == "0.00")
    }
}

@Suite("Speed delta to best")
struct SpeedDeltaTests {
    /// Three laps over 100 m each: 10 m/s, then 20 m/s (the best), then 15 m/s.
    static func session(laps: [Lap]) -> TelemetrySession {
        let times = Array(stride(from: 0.0, through: 22.0, by: 0.5))
        func speedAt(_ t: Double) -> Double { t < 10 ? 10 : t < 15 ? 20 : 15 }
        var distance: [Double] = []
        var travelled = 0.0
        for (index, t) in times.enumerated() {
            if index > 0 { travelled += speedAt(t - 0.25) * 0.5 }
            distance.append(travelled)
        }
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distance),
                Channel(role: .speed, name: "s", unit: .metersPerSecond, times: times, values: times.map(speedAt)),
            ], laps: laps)
    }

    @Test func compareSpeedAtTheSameDistance() {
        let laps = [
            Lap(number: 1, start: 0, end: 10, isComplete: true), Lap(number: 2, start: 10, end: 15, isComplete: true),
            Lap(number: 3, start: 15, end: nil, isComplete: false),
        ]
        let session = Self.session(laps: laps)
        // In lap 3 (15 m/s) the best lap (lap 2) ran 20 m/s at the same distance → −5 m/s.
        let delta = LapComparison.speedDeltaToBest(at: 17, session: session)
        #expect(delta != nil && abs((delta ?? 0) + 5) < 0.01, "delta \(String(describing: delta))")
        // With no completed best lap there is nothing to compare with.
        let first = Self.session(laps: [Lap(number: 1, start: 0, end: nil, isComplete: false)])
        #expect(LapComparison.speedDeltaToBest(at: 3, session: first) == nil)
    }
}

@Suite("Deltas to a reference lap")
struct ReferenceLapTests {
    /// 100 m laps at 10, 20 and 10 m/s, then a fourth at 15 m/s: lap 2 is the best, lap 3 the previous.
    static func session() -> TelemetrySession {
        let times = Array(stride(from: 0.0, through: 32.0, by: 0.5))
        func speedAt(_ t: Double) -> Double { t < 10 ? 10 : t < 15 ? 20 : t < 25 ? 10 : 15 }
        var distance: [Double] = []
        var travelled = 0.0
        for (index, t) in times.enumerated() {
            if index > 0 { travelled += speedAt(t - 0.25) * 0.5 }
            distance.append(travelled)
        }
        let laps = [
            Lap(number: 1, start: 0, end: 10, isComplete: true), Lap(number: 2, start: 10, end: 15, isComplete: true),
            Lap(number: 3, start: 15, end: 25, isComplete: true),
            Lap(number: 4, start: 25, end: nil, isComplete: false),
        ]
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(role: .distance, name: "d", unit: .meters, times: times, values: distance),
                Channel(role: .speed, name: "s", unit: .metersPerSecond, times: times, values: times.map(speedAt)),
            ], laps: laps)
    }

    @Test func bestAndPreviousLapsAreDifferentReferences() {
        let session = Self.session()
        #expect(LapComparison.referenceLap(at: 27, session: session, reference: .best)?.number == 2)
        #expect(LapComparison.referenceLap(at: 27, session: session, reference: .previous)?.number == 3)
        // 2 s into lap 4 = 30 m. Lap 2 got there in 1.5 s (behind by 0.5), lap 3 in 3 s (ahead by 1).
        let best = LapComparison.delta(at: 27, session: session, reference: .best)
        let previous = LapComparison.delta(at: 27, session: session, reference: .previous)
        #expect(best != nil && abs((best ?? 0) - 0.5) < 0.01, "best \(String(describing: best))")
        #expect(previous != nil && abs((previous ?? 0) + 1) < 0.01, "previous \(String(describing: previous))")
        // Speed: 15 m/s now against 20 (best) and 10 (previous) at the same spot.
        #expect(abs((LapComparison.speedDelta(at: 27, session: session, reference: .best) ?? 0) + 5) < 0.01)
        #expect(abs((LapComparison.speedDelta(at: 27, session: session, reference: .previous) ?? 0) - 5) < 0.01)
        // In lap 1 there is nothing to compare with either way.
        #expect(LapComparison.delta(at: 3, session: session, reference: .previous) == nil)
        #expect(LapComparison.deltaToBest(at: 3, session: session) == nil)
    }
}

@Suite("Lap delta channels")
struct LapDeltaChannelTests {
    @Test func channelsCompareEveryLapWithTheSessionBest() throws {
        // 100 m laps at 10, 20 (the best), 10 and then 15 m/s.
        let session = ReferenceLapTests.session()
        #expect(LapDeltas.sessionBest(in: session)?.number == 2)
        let channels = LapDeltas.channels(for: session)
        let delta = try #require(channels.first { $0.role == .lapDelta })
        let speed = try #require(channels.first { $0.role == .speedDelta })
        // Lap 1 already has a delta: 50 m in took 5 s, the best lap needed 2.5 s.
        #expect(abs((delta.value(at: 5) ?? 0) - 2.5) < 0.01)
        #expect(abs((speed.value(at: 5) ?? 0) + 10) < 0.01)
        // The best lap reads zero against itself.
        #expect(abs(delta.value(at: 12) ?? 1) < 0.001)
        #expect(abs(speed.value(at: 12) ?? 1) < 0.001)
        // Lap 4 (in progress, 15 m/s): 30 m in after 2 s, the best lap needed 1.5 s.
        #expect(abs((delta.value(at: 27) ?? 0) - 0.5) < 0.01)
        #expect(abs((speed.value(at: 27) ?? 0) + 5) < 0.01)
        // The timer's session-best reference agrees with the channel.
        let viaComparison = LapComparison.delta(at: 27, session: session, reference: .sessionBest)
        #expect(abs((viaComparison ?? 0) - 0.5) < 0.01)
        // In lap 1 "best so far" has nothing to compare with, the session best does.
        #expect(LapComparison.delta(at: 5, session: session, reference: .best) == nil)
        #expect(LapComparison.delta(at: 5, session: session, reference: .sessionBest) != nil)
    }

    @Test func aShortFragmentCannotBeTheBestLap() {
        // A 3 s "lap" of 30 m (pit-lane crossing) between two 100 m laps.
        let times = Array(stride(from: 0.0, through: 30.0, by: 0.5))
        let distance = times.map { $0 * 10 }
        let laps = [
            Lap(number: 1, start: 0, end: 10, isComplete: true), Lap(number: 2, start: 10, end: 13, isComplete: true),
            Lap(number: 3, start: 13, end: 23, isComplete: true),
            Lap(number: 4, start: 23, end: nil, isComplete: false),
        ]
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .distance, name: "d", unit: .meters, times: times, values: distance)], laps: laps)
        let demoted = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
        #expect(demoted.map(\.isComplete) == [true, false, true, false])
        #expect(LapDeltas.sessionBest(in: session)?.number == 1)
        // Without a distance channel nothing can be judged, so nothing changes.
        #expect(LapDeltas.demotingShortLaps(laps, distance: nil) == laps)
        // No speed channel: only the time delta is produced.
        #expect(LapDeltas.channels(for: session).map(\.role) == [.lapDelta])
    }

    @Test func sessionsWithoutLapsOrDistanceProduceNoChannels() {
        let empty = TelemetrySession(info: SessionInfo(sourceFormat: "test"), channels: [])
        #expect(LapDeltas.channels(for: empty).isEmpty)
        #expect(ChannelRole(identifier: "lapDelta") == .lapDelta)
        #expect(ChannelRole(identifier: "speedDelta") == .speedDelta)
    }
}
