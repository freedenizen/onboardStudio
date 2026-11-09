import Foundation
import Testing

@testable import ProjectModel

@Suite("Time map (#442)")
struct TimeMapTests {
    /// 0–0.5 normal, 0.5–1.5 at half speed, a 1 s hold at 2, the rest normal: a 3 s project
    /// that takes 5 s to play.
    static let map = TimeMap(
        retimes: [
            Retime(start: 0.5, kind: .speed(end: 1.5, rate: 0.5)),
            Retime(start: 2, kind: .hold(seconds: 1)),
        ], projectDuration: 3)

    @Test func noRetimesIsTheIdentity() {
        let map = TimeMap.identity(3)
        #expect(map.isIdentity && map.outputDuration == 3)
        for t in [0, 0.4, 1.7, 3] {
            #expect(map.projectTime(atOutput: t) == t && map.outputTime(atProject: t) == t)
        }
        #expect(map.retimedOutputRanges.isEmpty)
    }

    @Test func aSlowStretchAndAHoldLengthenTheOutput() {
        let map = Self.map
        #expect(!map.isIdentity)
        #expect(abs(map.outputDuration - 5) < 1e-9)
        // Before, inside, and after the slow stretch.
        #expect(abs(map.projectTime(atOutput: 0.25) - 0.25) < 1e-9)
        #expect(abs(map.projectTime(atOutput: 1.5) - 1.0) < 1e-9, "half way through the 2 s of output")
        #expect(abs(map.projectTime(atOutput: 2.75) - 1.75) < 1e-9)
        // The hold shows the same moment throughout, then plays on.
        #expect(map.projectTime(atOutput: 3.0) == 2 && map.projectTime(atOutput: 3.9) == 2)
        #expect(abs(map.projectTime(atOutput: 4.5) - 2.5) < 1e-9)
        #expect(map.projectTime(atOutput: 99) == 3)
        // The other way: a held moment is entered at the start of its hold.
        #expect(abs(map.outputTime(atProject: 1.0) - 1.5) < 1e-9)
        #expect(abs(map.outputTime(atProject: 2.0) - 3.0) < 1e-9)
        #expect(abs(map.outputTime(atProject: 2.5) - 4.5) < 1e-9)
        #expect(map.outputTime(atProject: 3) == 5)
        // Sound is muted over the slow stretch and the hold.
        #expect(map.retimedOutputRanges.count == 2)
        #expect(abs(map.retimedOutputRanges[0].lowerBound - 0.5) < 1e-9)
        #expect(abs(map.retimedOutputRanges[0].upperBound - 2.5) < 1e-9)
        #expect(map.retimedOutputRanges[1] == 3...4)
    }

    @Test func outputAndProjectTimeRoundTrip() {
        let map = Self.map
        for project in stride(from: 0.0, through: 3, by: 0.05) where abs(project - 2) > 1e-9 {
            #expect(abs(map.projectTime(atOutput: map.outputTime(atProject: project)) - project) < 1e-9)
        }
    }

    @Test func overlapsAreResolvedAndOutOfRangeRetimesDropped() {
        let map = TimeMap(
            retimes: [
                Retime(start: 1, kind: .speed(end: 2, rate: 0.5)),
                // Overlaps the first: plays from where the first ends.
                Retime(start: 1.5, kind: .speed(end: 2.5, rate: 2)),
                // Outside the project, a zero hold, a negative stretch.
                Retime(start: 5, kind: .hold(seconds: 1)),
                Retime(start: 0.2, kind: .hold(seconds: 0)),
                Retime(start: 2.9, kind: .speed(end: 2.8, rate: 0.5)),
                // Two holds at one moment add up, and a hold is capped.
                Retime(start: 0.5, kind: .hold(seconds: 1)),
                Retime(start: 0.5, kind: .hold(seconds: 100)),
            ], projectDuration: 3)
        // 0.5 normal + 31 s hold + 0.5 normal + 2 s (1 s at half) + 0.25 s (0.5 s at double) + 0.5 normal.
        #expect(abs(map.outputDuration - (0.5 + Retime.longestHold + 0.5 + 2 + 0.25 + 0.5)) < 1e-9)
        // A speed is clamped to the rates a stretch may play at.
        let crawl = TimeMap(retimes: [Retime(start: 0, kind: .speed(end: 1, rate: 0.001))], projectDuration: 1)
        #expect(abs(crawl.outputDuration - 1 / Retime.rates.lowerBound) < 1e-9)
    }

    @Test func aProjectSavedBeforeRetimesHasNone() throws {
        var json = try #require(
            try JSONSerialization.jsonObject(with: Project().encoded()) as? [String: Any])
        json.removeValue(forKey: "retimes")
        let project = try Project.decode(JSONSerialization.data(withJSONObject: json))
        #expect(project.retimes.isEmpty)
        // And a retime survives a save.
        var retimed = Project()
        retimed.retimes = [Retime(start: 1, kind: .hold(seconds: 0.5))]
        let reread = try Project.decode(retimed.encoded())
        #expect(reread.retimes == retimed.retimes)
    }
}
