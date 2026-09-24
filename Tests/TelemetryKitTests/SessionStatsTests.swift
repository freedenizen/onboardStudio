import Foundation
import Testing

@testable import TelemetryKit

@Suite("Session headline numbers (#151)")
struct SessionStatsTests {
    /// An out-lap, laps of 92 s and 90 s, and an in-lap; speed peaks at 60 m/s in the 92 s lap.
    let session: TelemetrySession = {
        let times: [Double] = [0, 30, 60, 100, 150, 200, 260, 300]
        let speeds: [Double] = [10, 30, 40, 60, 45, 55, 50, 20]
        return TelemetrySession(
            info: SessionInfo(sourceFormat: "test"),
            channels: [
                Channel(
                    role: .speed, name: "speed", unit: .metersPerSecond, times: times, values: speeds,
                    interpolation: .linear)
            ],
            laps: [
                Lap(number: 0, start: 0, end: 60, isComplete: false),
                Lap(number: 1, start: 60, end: 152, isComplete: true),
                Lap(number: 2, start: 152, end: 242, isComplete: true),
                Lap(number: 3, start: 242, end: nil, isComplete: false),
            ])
    }()

    @Test func theSessionLeadsWithItsBestCompleteLapAndTopSpeed() {
        let stats = SessionStats(session: session)
        #expect(stats.bestLap == SessionStats.LapTime(number: 2, seconds: 90))
        #expect(stats.topSpeed == 60)
        #expect(stats.completeLaps == 2)
        #expect(stats.lap == nil && stats.deltaToBest == nil)
    }

    @Test func oneLapSaysHowFarOffTheBestItWas() throws {
        let slower = SessionStats(lap: session.laps[1], in: session)
        #expect(slower.lap == SessionStats.LapTime(number: 1, seconds: 92))
        #expect(try #require(slower.deltaToBest) == 2)
        #expect(slower.topSpeed == 60)  // the peak was in this lap
        let best = SessionStats(lap: session.laps[2], in: session)
        #expect(best.deltaToBest == 0)
        #expect(best.topSpeed == 55)
        // A lap that never reached the line has no time to compare.
        let inLap = SessionStats(lap: session.laps[3], in: session)
        #expect(inLap.lap == nil && inLap.deltaToBest == nil)
        #expect(inLap.topSpeed == 50)
    }
}
