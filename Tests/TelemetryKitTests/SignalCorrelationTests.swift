import Foundation
import Testing

@testable import TelemetryKit

@Suite("Signal correlation")
struct SignalCorrelationTests {
    /// A "car moving" pattern: bursts of activity at known times, 10 Hz.
    static func bursts(duration: Double, rate: Double, at intervals: [ClosedRange<Double>], shift: Double = 0)
        -> [Double]
    {
        (0..<Int(duration * rate)).map { index in
            let t = Double(index) / rate - shift
            return intervals.contains { $0.contains(t) } ? 1.0 + 0.2 * sin(t * 3) : 0.05 * sin(t * 7)
        }
    }

    @Test func findsAKnownLag() throws {
        let rate = 10.0
        let intervals: [ClosedRange<Double>] = [3...5, 9...12, 15...16, 22...23.5]
        let short = Self.bursts(duration: 30, rate: rate, at: intervals)
        // The long signal contains the same bursts 47.3 s later, plus unrelated activity elsewhere.
        var long = Self.bursts(duration: 200, rate: rate, at: intervals, shift: 47.3)
        for index in 1200..<1300 { long[index] = 0.8 }
        let result = try #require(
            SignalCorrelation.bestOffset(
                short: SignalCorrelation.normalise(short, window: 50),
                long: SignalCorrelation.normalise(long, window: 50),
                rate: rate))
        #expect(abs(result.offset - 47.3) < 0.15, "offset \(result.offset)")
        #expect(result.score > 0.8)
        #expect(result.prominence > 0.3)
    }

    @Test func negativeLagsAndPartialOverlapWork() throws {
        let rate = 10.0
        let intervals: [ClosedRange<Double>] = [2...4, 7...9, 13...14]
        let short = Self.bursts(duration: 20, rate: rate, at: intervals)
        // The long signal starts 5 s after the short one (so the short signal's first bursts fall before it).
        let long = Self.bursts(duration: 60, rate: rate, at: intervals, shift: -5)
        let result = try #require(
            SignalCorrelation.bestOffset(
                short: SignalCorrelation.normalise(short, window: 50),
                long: SignalCorrelation.normalise(long, window: 50),
                rate: rate))
        #expect(abs(result.offset + 5) < 0.15, "offset \(result.offset)")
    }

    @Test func flatSignalsGiveNothing() {
        let flat = [Double](repeating: 1, count: 200)
        #expect(SignalCorrelation.bestOffset(short: flat, long: flat, rate: 10) == nil)
        #expect(SignalCorrelation.normalise(flat, window: 10).allSatisfy { $0 == 0 })
    }

    @Test func resampleInterpolatesToAUniformGrid() {
        let (start, values) = SignalCorrelation.resample(times: [1, 2, 4], values: [0, 10, 30], rate: 2)
        #expect(start == 1)
        #expect(values.count == 7)
        #expect(values[0] == 0 && values[1] == 5 && values[2] == 10 && values[4] == 20 && values[6] == 30)
    }
}

@Suite("Session builder hardening")
struct SessionBuilderHardeningTests {
    @Test func dropsNonFiniteAndNonIncreasingTimes() {
        let table = RawTable(
            info: SessionInfo(sourceFormat: "test"), times: [0, 1, .nan, 2, 1.5, 3, .infinity, 4],
            columns: [
                RawColumn(
                    name: "Speed", unit: .metersPerSecond, suggestedRole: .speed,
                    values: [10, 11, 12, 13, 14, 15, 16, 17])
            ])
        let session = SessionBuilder.build(table)
        let speed = session[.speed]
        #expect(speed?.times == [0, 1, 2, 3, 4])
        #expect(speed?.values == [10, 11, 13, 15, 17])
        #expect(session.timeRange == 0...4)
    }

    @Test func timeRangeIsNilWhenChannelsDisagree() {
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [Channel(role: .speed, name: "s", unit: .metersPerSecond, times: [.nan], values: [1])], laps: [])
        #expect(session.timeRange == nil)
        #expect(TimeParsing.lapTimeString(.infinity) == "0:00.00")
        #expect(TimeParsing.lapTimeString(1e300).hasPrefix("99:59:59"))
    }
}
