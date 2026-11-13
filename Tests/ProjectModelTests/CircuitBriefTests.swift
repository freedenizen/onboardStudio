import Foundation
import Testing

@testable import ProjectModel

@Suite("Before going back to a circuit (#460)")
struct CircuitBriefTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    static func date(_ month: Int, _ day: Int, hour: Int = 11) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour)) ?? .distantPast
    }

    static func corner(_ label: String, brake: Double?, minimum: Double, time: Double) -> CornerRecord {
        CornerRecord(
            index: 0, label: label, brakePointMeters: brake, minimumSpeed: minimum, exitSpeed: 30, timeInCorner: time)
    }

    static func session(
        _ hash: String, on date: Date, best: Double?, corners: [CornerRecord] = [], track: String = "Stadium",
        car: String = "Miata"
    ) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"), trackName: track,
            date: date, car: car, bestLap: best, bestLapNumber: best == nil ? nil : 1, corners: corners)
    }

    /// The best in September; two sessions in November, slower through turns 2 and 4.
    static var entries: [LogbookEntry] {
        let best = [
            corner("1", brake: 90, minimum: 30, time: 5.00), corner("2", brake: 80, minimum: 20, time: 6.00),
            corner("3", brake: 70, minimum: 25, time: 4.00), corner("4", brake: 60, minimum: 18, time: 7.00),
        ]
        let latest = [
            corner("1", brake: 90, minimum: 30, time: 5.02), corner("2", brake: 95, minimum: 20, time: 6.40),
            corner("3", brake: 70, minimum: 25, time: 4.10), corner("4", brake: 60, minimum: 16.5, time: 7.70),
        ]
        return [
            session("a", on: date(9, 20), best: 60.0, corners: best),
            session("b", on: date(11, 8), best: 61.2, corners: latest),
            session("c", on: date(11, 8, hour: 15), best: 61.9, corners: latest),
            session("o", on: date(10, 1), best: 90.0, track: "Hilltop"),
        ]
    }

    @Test func theBriefHasTheBestTheLastVisitAndTheCornersThatLostMost() throws {
        let brief = CircuitBrief.make(entries: Self.entries, circuitKey: "Stadium", calendar: Self.calendar)
        #expect(brief.visits == 2)
        #expect(brief.personalBest?.seconds == 60.0)
        let november = Self.calendar.startOfDay(for: Self.date(11, 8))
        #expect(brief.lastVisit == CircuitBrief.Visit(date: november, best: 61.2, sessions: 2))
        // Turn 1 lost 0.02 s: not worth a line. The most first.
        #expect(brief.cornersToWorkOn.map(\.label) == ["4", "2", "3"])
        let four = try #require(brief.cornersToWorkOn.first)
        #expect(abs(four.timeLost - 0.70) < 0.001)
        #expect(abs((four.slowerAtApexBy ?? 0) - 1.5) < 0.001)
        #expect(brief.cornersToWorkOn[1].brakedEarlierBy == 15)
    }

    @Test func aCircuitVisitedOnceHasNothingToCompare() {
        let corner = Self.corner("1", brake: 90, minimum: 30, time: 5)
        let once = [Self.session("a", on: Self.date(9, 20), best: 60.0, corners: [corner])]
        let brief = CircuitBrief.make(entries: once, circuitKey: "Stadium", calendar: Self.calendar)
        #expect(brief.visits == 1)
        #expect(brief.cornersToWorkOn.isEmpty)
        #expect(CircuitBrief.make(entries: once, circuitKey: "Elsewhere", calendar: Self.calendar).isEmpty)
        #expect(CircuitBrief.make(entries: once, circuitKey: "", calendar: Self.calendar).isEmpty)
    }

    @Test func aPlanIsBegunFromTheCornersToWorkOn() {
        let brief = CircuitBrief.make(entries: Self.entries, circuitKey: "Stadium", calendar: Self.calendar)
        let plan = brief.startingPlan(made: Self.date(11, 12))
        #expect(plan.experiments.map(\.cornerLabel) == ["4", "2", "3"])
        #expect(plan.experiments[0].text.hasPrefix("Carry more speed to the apex — 0.70 s lost"))
        #expect(plan.experiments[1].text.hasPrefix("Brake later — 15 m earlier than on your best lap"))
        #expect(plan.experiments[2].text == "Find the 0.10 s your best lap was quicker through here.")
        // With nothing to compare, one line to write in, for the lap as a whole.
        let once = CircuitBrief.make(entries: [Self.entries[0]], circuitKey: "Stadium", calendar: Self.calendar)
        #expect(once.startingPlan().experiments.map(\.cornerLabel) == [""])
    }

    @Test func aPlanIsForgottenWithItsLastExperiment() throws {
        let library = TrackLibrary(
            directory: FileManager.default.temporaryDirectory.appending(path: "plans-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: library.directory) }
        let plan = NextSessionPlan(experiments: [PlannedExperiment(cornerLabel: "4", text: "Brake later")])
        try library.remember(plan, id: "Q1") {
            TrackDefinition(circuitID: "Q1", name: "Stadium", latitude: 1, longitude: 2)
        }
        #expect(library.definition(id: "Q1")?.plan == plan)
        try library.forgetPlan(id: "Q1")
        #expect(library.definition(id: "Q1")?.plan == nil)
        #expect(library.definition(id: "Q1")?.name == "Stadium", "the definition stays")
        try library.forgetPlan(id: "Q9")
    }
}
