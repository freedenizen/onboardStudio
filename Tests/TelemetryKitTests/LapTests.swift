import Testing

@testable import TelemetryKit

@Suite("Lap timing")
struct LapTests {
    let laps = [
        Lap(number: 0, start: 0, end: 60, isComplete: true),
        Lap(number: 1, start: 60, end: 115, isComplete: true),
        Lap(number: 2, start: 115, end: 180, isComplete: true),
        Lap(number: 3, start: 180, end: 200, isComplete: false),
    ]

    @Test func resolvesCurrentLapAndElapsed() {
        let timing = LapTiming.resolve(at: 130, laps: laps)
        #expect(timing.currentLap?.number == 2)
        #expect(timing.elapsedInLap == 15)
    }

    @Test func lastAndBestLapOnlyCountCompletedLaps() {
        let timing = LapTiming.resolve(at: 130, laps: laps)
        #expect(timing.lastLapTime == 55)
        #expect(timing.bestLapTime == 55)
        #expect(timing.bestLapNumber == 1)
        let later = LapTiming.resolve(at: 190, laps: laps)
        #expect(later.lastLapTime == 65)
        #expect(later.bestLapTime == 55)
        #expect(later.currentLap?.isComplete == false)
    }

    @Test func beforeAnyLapCompletes() {
        let timing = LapTiming.resolve(at: 10, laps: laps)
        #expect(timing.currentLap?.number == 0)
        #expect(timing.lastLapTime == nil)
        #expect(timing.bestLapTime == nil)
    }

    @Test func lapTimeFormatting() {
        #expect(TimeParsing.lapTimeString(83.456) == "1:23.46")
        #expect(TimeParsing.lapTimeString(3725.5) == "1:02:05.50")
        #expect(TimeParsing.lapTimeString(0) == "0:00.00")
    }

    @Test(arguments: [("00:02:23.07", 143.07), ("2:23.07", 143.07), ("12.5", 12.5), ("1,5", 1.5)])
    func parsesTimeStrings(text: String, seconds: Double) {
        #expect(abs((TimeParsing.seconds(from: text) ?? -1) - seconds) < 1e-9)
    }

    @Test func rejectsGarbageTimes() {
        #expect(TimeParsing.seconds(from: "") == nil)
        #expect(TimeParsing.seconds(from: "a:b") == nil)
        #expect(TimeParsing.seconds(from: "1:2:3:4") == nil)
    }
}
