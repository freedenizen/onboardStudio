import Foundation
import MediaKit
import ProjectModel
import TelemetryKit
import Testing

@Suite("Every lap, one file each (#150)")
struct LapExportsTests {
    /// An out-lap, three flying laps (one a cool-down) and an in-lap that never reaches the line.
    let laps = [
        Lap(number: 0, start: 0, end: 70, isComplete: false),
        Lap(number: 1, start: 70, end: 160, isComplete: true),
        Lap(number: 2, start: 160, end: 248, isComplete: true),
        Lap(number: 3, start: 248, end: 360, isComplete: true),
        Lap(number: 4, start: 360, end: nil, isComplete: false),
    ]

    func exports(completeOnly: Bool = true, slowerThanBest: Double? = nil, duration: Double = 1_000) -> [LapExport] {
        ProjectCompiler.lapExports(
            laps: laps, sessionEnd: 420, sync: .identity, duration: duration,
            keeping: LapSelection(completeOnly: completeOnly, slowerThanBest: slowerThanBest))
    }

    @Test func completeLapsOnlyLeavesOutTheOutAndInLaps() {
        #expect(exports().map(\.lap) == [1, 2, 3])
        #expect(exports().first?.range == 70...160)
        // With them, the in-lap runs to the end of the data.
        let all = exports(completeOnly: false)
        #expect(all.map(\.lap) == [0, 1, 2, 3, 4])
        #expect(all.last?.range == 360...420)
    }

    @Test func slowLapsAreLeftOutAgainstTheBestCompleteLap() {
        // Best is lap 2 at 88 s; lap 3 at 112 s is 27 % slower, lap 1 at 90 s only 2 %.
        #expect(exports(slowerThanBest: 0.10).map(\.lap) == [1, 2])
        #expect(exports(slowerThanBest: 0.30).map(\.lap) == [1, 2, 3])
    }

    @Test func lapsAreMappedIntoProjectTimeAndClippedToIt() {
        // The data starts 20 s before the video: lap 1 is at 50–140 in the project.
        let sync = SyncSettings(offsetInProject: -20)
        let shifted = ProjectCompiler.lapExports(
            laps: laps, sessionEnd: 420, sync: sync, duration: 200, keeping: LapSelection())
        #expect(shifted.map(\.lap) == [1, 2])
        #expect(shifted.first?.range == 50...140)
        #expect(shifted.last?.range == 140...200)  // lap 2 clipped at the project's end
    }

    @Test func eachFileIsNamedForItsLap() {
        let lap = LapExport(lap: 7, range: 0...1)
        #expect(lap.fileName(base: "Sonoma", fileExtension: "mp4") == "Sonoma – Lap 7.mp4")
    }

    @Test func theLapAtThePlayheadIsTheOneStartingOnTheLine() {
        let all = exports(completeOnly: false)
        #expect(ProjectCompiler.lap(at: 100, in: all)?.lap == 1)
        #expect(ProjectCompiler.lap(at: 160, in: all)?.lap == 2)
        #expect(ProjectCompiler.lap(at: 420, in: all)?.lap == 4)
        #expect(ProjectCompiler.lap(at: 500, in: all) == nil)
    }
}
