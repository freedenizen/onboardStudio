import Foundation
import Testing

@testable import ProjectModel

@Suite("Progress after an import (#459)")
struct ImportProgressTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }

    static func date(_ month: Int, _ day: Int, year: Int = 2026, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? Date()
    }

    static func entry(_ hash: String, at track: String = "Stadium", on date: Date?, best: Double?) -> LogbookEntry {
        LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"),
            trackName: track.isEmpty ? nil : track, date: date, bestLap: best, added: Self.date(11, 12))
    }

    static func progress(_ entries: [LogbookEntry], added hashes: Set<String>) -> ImportProgress {
        ImportProgress.make(
            added: Set(entries.filter { hashes.contains($0.file.contentHash) }.map(\.id)), in: entries,
            calendar: calendar)
    }

    @Test func aQuickerDayIsComparedWithTheLastVisitAndOpensTrends() throws {
        let entries = [
            Self.entry("a", on: Self.date(9, 20), best: 62.10),
            Self.entry("b", on: Self.date(10, 12), best: 61.50),
            Self.entry("c", on: Self.date(10, 12, hour: 15), best: 61.20),
            Self.entry("d", on: Self.date(11, 8), best: 60.40),
            Self.entry("e", on: Self.date(11, 8, hour: 14), best: 60.95),
        ]
        let progress = Self.progress(entries, added: ["d", "e"])
        let circuit = try #require(progress.circuits.first)
        #expect(progress.circuits.count == 1)
        #expect(circuit.title == "Stadium")
        #expect(circuit.best == 60.40)
        #expect(circuit.sessions == 2)
        // The last visit is the latest earlier day, its best the quickest of its sessions.
        #expect(
            circuit.previous
                == ImportProgress.Visit(date: Self.calendar.startOfDay(for: Self.date(10, 12)), best: 61.20))
        #expect(circuit.isPersonalBest)
        #expect(!circuit.isFirstVisit)
        let when = ImportProgress.Circuit.date(try #require(circuit.previous).date, from: circuit.day)
        #expect(
            circuit.sentence
                == "Stadium: best lap 1:00.40, 0.80 s quicker than your last visit (\(when)) — a personal best.")
        #expect(progress.destination == .trends(circuit: "Stadium", title: "Stadium"))
    }

    @Test func aSlowerOrEqualDaySaysSoWithNoPersonalBest() throws {
        let slower = [
            Self.entry("a", on: Self.date(10, 12), best: 61.20), Self.entry("b", on: Self.date(11, 8), best: 61.95),
        ]
        let circuit = try #require(Self.progress(slower, added: ["b"]).circuits.first)
        #expect(!circuit.isPersonalBest)
        #expect(circuit.sentence.hasPrefix("Stadium: best lap 1:01.95, 0.75 s slower than your last visit ("))
        #expect(circuit.sentence.hasSuffix(")."))

        let level = [
            Self.entry("a", on: Self.date(10, 12), best: 61.20), Self.entry("b", on: Self.date(11, 8), best: 61.201),
        ]
        let same = try #require(Self.progress(level, added: ["b"]).circuits.first)
        #expect(!same.isPersonalBest)
        #expect(same.sentence.contains("1:01.20, the same as your last visit"))
    }

    @Test func anOlderDayAddedLaterIsComparedWithTheVisitBeforeIt() throws {
        let entries = [
            Self.entry("a", on: Self.date(5, 3), best: 63.00),
            Self.entry("b", on: Self.date(11, 8), best: 60.00),
            Self.entry("c", on: Self.date(7, 19), best: 62.40),
        ]
        let circuit = try #require(Self.progress(entries, added: ["c"]).circuits.first)
        #expect(circuit.hasLaterVisits)
        #expect(circuit.previous?.best == 63.00)
        // Quicker than the visit before it, not than November: no personal best.
        #expect(!circuit.isPersonalBest)
        #expect(circuit.sentence.contains("0.60 s quicker than the visit before it ("))
    }

    @Test func aFirstVisitPointsAtTheSeasonUntilTrendsHasTwoSessions() throws {
        let one = [Self.entry("a", on: Self.date(11, 8), best: 75.25)]
        let first = Self.progress(one, added: ["a"])
        let circuit = try #require(first.circuits.first)
        #expect(circuit.isFirstVisit)
        #expect(!circuit.hasTrend)
        #expect(circuit.sentence == "First visit to Stadium: best lap 1:15.25. Trends begins with your next day there.")
        #expect(first.destination == .season)

        // Two sessions on the first day are already a trend through the day.
        let two = one + [Self.entry("b", on: Self.date(11, 8, hour: 15), best: 74.80)]
        let both = Self.progress(two, added: ["b"])
        #expect(
            try #require(both.circuits.first).sentence == "First visit to Stadium: best lap 1:14.80 over 2 sessions.")
        #expect(both.destination == .trends(circuit: "Stadium", title: "Stadium"))
    }

    @Test func noLapTimeOnEitherSideIsSaidPlainly() throws {
        let none = [
            Self.entry("a", on: Self.date(10, 12), best: 61.20), Self.entry("b", on: Self.date(11, 8), best: nil),
        ]
        let circuit = try #require(Self.progress(none, added: ["b"]).circuits.first)
        #expect(circuit.sentence.hasPrefix("Stadium: no complete lap this time to compare with your last visit ("))

        let untimed = [
            Self.entry("a", on: Self.date(10, 12), best: nil), Self.entry("b", on: Self.date(11, 8), best: 60.0),
        ]
        let earlier = try #require(Self.progress(untimed, added: ["b"]).circuits.first)
        #expect(earlier.previous == nil)
        #expect(earlier.sentence == "Stadium: best lap 1:00.00. No earlier visit has a lap time to compare it with.")
    }

    @Test func severalCircuitsAreEachALineNewestFirstAndOpenTheSeason() {
        let entries = [
            Self.entry("a", at: "Hilltop", on: Self.date(10, 4), best: 90.0),
            Self.entry("b", at: "Hilltop", on: Self.date(11, 1), best: 89.0),
            Self.entry("c", on: Self.date(11, 8), best: 60.0),
            Self.entry("d", at: "", on: Self.date(11, 8), best: 58.0),
        ]
        let progress = Self.progress(entries, added: ["b", "c", "d"])
        // A session that names no circuit is not a visit anywhere (#455).
        #expect(progress.circuits.map(\.title) == ["Stadium", "Hilltop"])
        #expect(progress.destination == .season)
    }

    @Test func nothingNewSaysNothing() {
        let entries = [Self.entry("a", on: Self.date(10, 12), best: 61.20)]
        let progress = Self.progress(entries, added: [])
        #expect(progress.circuits.isEmpty)
        #expect(progress.destination == nil)
    }

    @Test func anotherYearIsWrittenWithTheDate() {
        let november = Self.date(11, 8)
        #expect(
            ImportProgress.Circuit.date(Self.date(10, 12), from: november)
                == Self.date(10, 12).formatted(.dateTime.day().month(.abbreviated)))
        #expect(
            ImportProgress.Circuit.date(Self.date(10, 12, year: 2025), from: november)
                == Self.date(10, 12, year: 2025).formatted(.dateTime.day().month(.abbreviated).year()))
    }
}
