import Foundation
import Testing

@testable import ProjectModel

@Suite("Goals (#461)")
struct GoalTests {
    static func date(_ month: Int, _ day: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))
            ?? .distantPast
    }

    static func session(
        _ hash: String, _ month: Int, _ day: Int, laps: [Double], car: String = "Miata", track: String = "Stadium",
        corners: [CornerRecord] = []
    ) -> LogbookEntry {
        let records = laps.enumerated().map {
            LogbookEntry.LapRecord(number: $0.offset + 1, seconds: $0.element, isComplete: true)
        }
        return LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"), trackName: track,
            date: date(month, day), car: car, laps: records, bestLap: laps.min(), corners: corners)
    }

    static func corner(_ label: String, time: Double, minimum: Double) -> CornerRecord {
        CornerRecord(
            index: 0, label: label, brakePointMeters: 80, minimumSpeed: minimum, exitSpeed: 30, timeInCorner: time)
    }

    static var entries: [LogbookEntry] {
        [
            session("a", 9, 20, laps: [62.0, 62.4, 62.9, 63.1], corners: [corner("4", time: 7.0, minimum: 18)]),
            session("b", 10, 12, laps: [61.0, 61.1, 61.2, 61.3], corners: [corner("4", time: 6.6, minimum: 19.5)]),
            session("c", 11, 8, laps: [60.4, 61.9, 62.5], car: "GR86"),
            session("o", 10, 1, laps: [50.0], track: "Hilltop"),
        ]
    }

    @Test func aLapTimeGoalIsMeasuredAgainstTheBestThere() {
        let goal = Goal(circuitKey: "Stadium", target: .lapTime(seconds: 60.0))
        let progress = GoalProgress.make(goal, entries: Self.entries)
        #expect(progress.best == 60.4)
        #expect(!progress.isReached)
        #expect(abs((progress.remaining ?? 0) - 0.4) < 0.001)
        #expect(progress.status(speed: .kph) == "Best 1:00.40 — 0.40 s to go")
        // In one car only: the GR86's quicker lap does not count.
        var miata = goal
        miata.car = "miata"
        #expect(GoalProgress.make(miata, entries: Self.entries).best == 61.0)
        // Reached on the first day that met it.
        let met = GoalProgress.make(Goal(circuitKey: "Stadium", target: .lapTime(seconds: 61.5)), entries: Self.entries)
        #expect(met.reachedOn == Self.date(10, 12))
        #expect(met.remaining == 0)
        #expect(met.status(speed: .kph).hasPrefix("Reached on "))
    }

    @Test func consistencyAndCornerGoalsReadTheirOwnMeasure() throws {
        let steady = Goal(circuitKey: "Stadium", target: .consistency(seconds: 0.2))
        let progress = GoalProgress.make(steady, entries: Self.entries)
        // The October session's four laps spread by 0.13 s; September's by more.
        #expect(progress.isReached)
        #expect(progress.reachedOn == Self.date(10, 12))
        let cornerGoal = Goal(circuitKey: "Stadium", target: .cornerTime(label: "4", seconds: 6.5))
        let time = GoalProgress.make(cornerGoal, entries: Self.entries)
        #expect(abs((time.remaining ?? 0) - 0.1) < 0.001)
        // Speed is better when higher.
        let speed = Goal(circuitKey: "Stadium", target: .cornerSpeed(label: "4", metersPerSecond: 20))
        let apex = GoalProgress.make(speed, entries: Self.entries)
        #expect(apex.best == 19.5 && !apex.isReached)
        #expect(abs((apex.remaining ?? 0) - 0.5) < 0.001)
        #expect(speed.title(speed: .kph) == "72 km/h at turn 4's apex")
        #expect(steady.title(speed: .kph) == "flying laps within 0.20 s")
        let nowhere = Goal(circuitKey: "Nowhere", target: .lapTime(seconds: 1))
        #expect(GoalProgress.make(nowhere, entries: Self.entries).status(speed: .kph) == "Nothing measured yet")
    }

    @Test func anImportSaysWhenAGoalIsReachedOrCloser() {
        let entries = Self.entries
        let lap = Goal(circuitKey: "Stadium", target: .lapTime(seconds: 60.5))
        let far = Goal(circuitKey: "Stadium", target: .lapTime(seconds: 59.0))
        let elsewhere = Goal(circuitKey: "Hilltop", target: .lapTime(seconds: 40.0))
        let added = Set([entries[2].id])
        let news = GoalNews.make(goals: [lap, far, elsewhere], added: added, in: entries, speed: .kph)
        #expect(news.map(\.reached) == [true, false])
        #expect(news[0].sentence == "Goal reached: 1:00.50 lap at Stadium.")
        #expect(news[1].sentence == "1.40 s to go to your 0:59.00 lap at Stadium, 0.60 s closer than before.")
    }

    @Test func goalsAreKeptBesideTheGarageAndTravelWithAnExport() throws {
        let logbook = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "goals-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let goals = [
            Goal(circuitKey: "Stadium", target: .lapTime(seconds: 60), car: "Miata", by: Self.date(12, 1)),
            Goal(circuitKey: "Stadium", target: .cornerSpeed(label: "4", metersPerSecond: 20)),
        ]
        try logbook.saveGoals(goals)
        #expect(logbook.goals() == goals)
        let folder = FileManager.default.temporaryDirectory.appending(path: "goals-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        try LogbookTransfer.export([], goals: goals, to: folder)
        let other = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "goals-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: other.directory) }
        try other.saveGoals([goals[0]])
        try LogbookTransfer.import(from: folder, into: other)
        #expect(Set(other.goals()) == Set(goals), "one already there, one added")
    }
}
