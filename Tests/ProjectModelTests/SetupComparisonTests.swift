import Foundation
import Testing

@testable import ProjectModel

/// #559: Trends narrowed by the tyres, setup and conditions, and two ways of driving compared.
@Suite("Setup comparison in Trends (#559)")
struct SetupComparisonTests {
    static let units = SetupUnits(pressure: .psi, length: .inches)

    /// A session at Stadium on `day`, its laps' sectors given, its best lap through two corners.
    static func session(
        _ hash: String, day: Int, tyres: String = "", setup: String = "", cold: Double? = nil,
        surface: SessionConditions.Track? = nil, sectors: [[Double]], turn1: Double = 20, turn2: Double = 15
    ) -> LogbookEntry {
        var entry = GarageTests.entry(hash, car: "Miata", on: GarageTests.date(9, day))
        entry.conditions = SessionConditions(track: surface, tyres: tyres)
        entry.conditions.sheet.name = setup
        if let cold { SetupItem.coldPressure(.rearLeft).set(String(cold), in: &entry.conditions.sheet, units: units) }
        entry.laps = sectors.enumerated().map { index, splits in
            LogbookEntry.LapRecord(
                number: index + 1, seconds: splits.reduce(0, +), isComplete: true, sectors: splits.map(Optional.some))
        }
        entry.bestLap = entry.laps.compactMap(\.seconds).min()
        entry.optimalLap = entry.bestLap.map { $0 - 0.1 }
        entry.corners = [
            CornerRecord(
                index: 0, label: "Turn 1", brakePointMeters: 50, minimumSpeed: turn1, exitSpeed: 30, timeInCorner: 4),
            CornerRecord(
                index: 1, label: "Turn 2", brakePointMeters: 40, minimumSpeed: turn2, exitSpeed: 25, timeInCorner: 3),
        ]
        return entry
    }

    static let sessions = [
        session(
            "a", day: 1, tyres: "RE-71RS", setup: "Base", cold: 30, surface: .dry, sectors: [[30, 31], [29.8, 31.2]]),
        session("b", day: 2, tyres: "RE-71RS", setup: "Base", cold: 30, surface: .dry, sectors: [[30.2, 30.8]]),
        session(
            "c", day: 3, tyres: "RE-71RS", setup: "Soft rear", cold: 28, surface: .dry, sectors: [[29.5, 31.3]],
            turn1: 21),
        session(
            "d", day: 4, tyres: "Hoosier", setup: "Soft rear", cold: 28, surface: .wet, sectors: [[29.4, 31.4]],
            turn1: 21, turn2: 14),
    ]

    // MARK: - Filters

    @Test func theFiltersOfferWhatTheSessionsNotedInTheOrderDriven() {
        let choices = TrendsFilter.choices(in: Self.sessions.reversed())
        #expect(choices.tyres == ["RE-71RS", "Hoosier"])
        #expect(choices.setups == ["Base", "Soft rear"])
        #expect(choices.surfaces == [.dry, .wet])
        #expect(choices.weathers.isEmpty)
    }

    @Test func aFilterKeepsOnlyTheSessionsDrivenThatWay() {
        let filter = TrendsFilter(tyres: "re-71rs", surface: .dry)
        #expect(Self.sessions.filter(filter.matches).map(\.file.contentHash) == ["a", "b", "c"])
        #expect(TrendsFilter().isEmpty)
    }

    // MARK: - Before and after

    @Test func onlyWhatTheSessionsDifferByIsOffered() {
        let splits = SetupComparison.splits(in: Self.sessions)
        #expect(splits.prefix(3) == [.tyres, .setup, .surface])
        #expect(splits.contains(.item(.coldPressure(.rearLeft))))
        #expect(!splits.contains(.item(.camber(.frontLeft))))
    }

    @Test func twoSetupsAreReadAcrossTheLapEverySectorAndEveryCorner() throws {
        let dry = Self.sessions.filter { $0.conditions.track == .dry }
        let values = SetupComparison.values(of: .setup, in: dry, units: Self.units)
        #expect(values.map(\.label) == ["Base", "Soft rear"])
        let comparison = try #require(
            SetupComparison.compare(.setup, before: "base", after: "soft rear", in: dry, units: Self.units))
        #expect(comparison.before.sessions == 2 && comparison.after.sessions == 1)
        // Bests 61.0 (a) and 61.0 (b) average 61.0; the soft rear's 60.8 is 0.2 quicker.
        #expect(abs(try #require(comparison.averageBestDifference) + 0.2) < 1e-9)
        #expect(comparison.before.sectors == [29.8, 30.8])
        let sectors = comparison.sectorDifferences.compactMap { $0 }
        #expect(abs(sectors[0] + 0.3) < 1e-9 && abs(sectors[1] - 0.5) < 1e-9)
        #expect(comparison.sectorSentence() == "Quicker in sector 1; slower in sector 2.")
        #expect(comparison.cornerDifferences.map(\.label) == ["Turn 1", "Turn 2"])
        #expect(comparison.cornerDifferences.first?.minimumSpeed == 1)
        #expect(
            comparison.headline
                == "Soft rear: each session's best averaged 0.20 s quicker than Base (1 session against 2).")
        #expect(comparison.caveats == ["One session on a side: a difference this size may be the day, not the change."])
    }

    @Test func aPressureCanBeComparedAsAValue() throws {
        let split = SetupSplit.item(.coldPressure(.rearLeft))
        let values = SetupComparison.values(of: split, in: Self.sessions, units: Self.units)
        #expect(values.map(\.label) == ["30 psi", "28 psi"])
        let comparison = try #require(
            SetupComparison.compare(
                split, before: values[0].key, after: values[1].key, in: Self.sessions, units: Self.units))
        #expect(comparison.after.sessions == 2)
    }

    @Test func aChangeThatCameWithOtherConditionsSaysSo() throws {
        let comparison = try #require(
            SetupComparison.compare(.tyres, before: "re-71rs", after: "hoosier", in: Self.sessions, units: Self.units))
        #expect(comparison.caveats.contains { $0.hasPrefix("The surface differed too (Dry against Wet)") })
    }

    @Test func sessionsCutIntoDifferentSectorsAreNotComparedBySector() throws {
        var sessions = Self.sessions
        sessions[3].laps[0].sectors = [10, 10, 10]
        let comparison = try #require(
            SetupComparison.compare(.tyres, before: "re-71rs", after: "hoosier", in: sessions, units: Self.units))
        #expect(comparison.sectorDifferences.isEmpty)
        #expect(comparison.sectorSentence() == nil)
    }
}
