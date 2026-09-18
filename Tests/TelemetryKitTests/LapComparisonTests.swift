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
