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

    // MARK: - A session whose file gives no date (#656)

    /// A clip with no clock, added with a day's files months after the day: it is on that day, and
    /// was counted as a second visit on the day of the import.
    @Test func aSessionWithNoDateCountsOnTheDayItIsOnNotTheDayItWasAdded() throws {
        // A day is the day of the Mac's own calendar, as `TrackDay` keeps it.
        let local = Calendar(identifier: .gregorian)
        let driven = try #require(local.date(from: DateComponents(year: 2026, month: 9, day: 20, hour: 11)))
        let imported = try #require(local.date(from: DateComponents(year: 2026, month: 11, day: 22, hour: 21)))
        let day = TrackDay(date: TrackDay.startOfDay(driven), trackName: "Stadium")
        var logged = Self.session("a", on: driven, best: 60.0)
        logged.trackDayID = day.id
        logged.dayDate = day.date
        var clip = LogbookEntry(
            file: .init(path: "/d/clip.mp4", contentHash: "clip", byteCount: 1, importerID: "x"), trackName: "Stadium",
            date: nil, trackDayID: day.id, added: imported)
        #expect(clip.when == imported, "on no day it knows of, it is still counted when it was added")
        #expect(CircuitBrief.make(entries: [logged, clip], circuitKey: "Stadium", calendar: local).visits == 2)
        clip.dayDate = day.date
        #expect(clip.when == day.date && clip.year == 2026)

        let brief = CircuitBrief.make(entries: [logged, clip], circuitKey: "Stadium", calendar: local)
        #expect(brief.visits == 1)
        let last = try #require(brief.lastVisit)
        #expect(last.date == day.date && last.sessions == 2 && last.best == 60.0)
        #expect(PersonalBests.trackDays(in: [logged, clip], circuitKey: "Stadium", calendar: local) == 1)
        #expect(SeasonSummary.make(entries: [logged, clip], year: 2026).trackDays == 1)
    }

    /// The logbook fills the day's date in as it reads an entry, and never writes it.
    @Test func theLogbookReadsEachSessionWithTheDateOfItsDay() throws {
        let logbook = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "daydate-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = TrackDay(date: TrackDay.startOfDay(Self.date(9, 20)), trackName: "Stadium")
        try logbook.saveDay(day)
        let clip = LogbookEntry(
            file: .init(path: "/d/clip.mp4", contentHash: "clip", byteCount: 1, importerID: "x"), trackName: "Stadium",
            date: nil, trackDayID: day.id, added: Self.date(11, 22))
        let loose = LogbookEntry(
            file: .init(path: "/d/loose.csv", contentHash: "loose", byteCount: 1, importerID: "x"), date: nil,
            added: Self.date(11, 22))
        try logbook.save(clip)
        try logbook.save(loose)

        let read = logbook.entries()
        #expect(read.first { $0.id == clip.id }?.dayDate == day.date)
        #expect(read.first { $0.id == clip.id } == logbook.entry(id: clip.id), "read alone, it is the same entry")
        #expect(read.first { $0.id == loose.id }?.dayDate == nil)
        #expect(read.first?.id == clip.id, "listed by its day's date, before a session with none at all")
        let file = try String(contentsOf: logbook.url(for: clip.id), encoding: .utf8)
        #expect(!file.contains("dayDate"))
    }
}
