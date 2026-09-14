import Testing

@testable import TelemetryKit

@Suite("TelemetrySampler")
struct SamplerTests {
    @Test func samplesEveryChannelAndLapTiming() {
        let session = TelemetrySession(
            info: SessionInfo(sourceFormat: "t"),
            channels: [
                Channel(role: .speed, name: "S", unit: .metersPerSecond, times: [0, 10], values: [0, 100]),
                Channel(role: .gear, name: "G", unit: .count, times: [0, 5], values: [1, 2], interpolation: .step),
            ],
            laps: [
                Lap(number: 0, start: 0, end: 4, isComplete: true),
                Lap(number: 1, start: 4, end: 10, isComplete: false),
            ])
        let sampler = TelemetrySampler(session: session)
        let sample = sampler.sample(at: 6)
        #expect(sample[.speed] == 60)
        #expect(sample[.gear] == 2)
        #expect(sample[.rpm] == nil)
        #expect(sample.lapTiming.currentLap?.number == 1)
        #expect(sample.lapTiming.elapsedInLap == 2)
        #expect(sample.lapTiming.lastLapTime == 4)
        #expect(sampler.value(of: .speed, at: 2.5) == 25)
    }
}
