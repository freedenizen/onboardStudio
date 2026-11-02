import Foundation
import Testing

@testable import ProjectModel

@Suite("Season summary (#355)")
struct SeasonSummaryTests {
    struct Spec {
        var hash: String
        var circuit: String
        var day: String
        var car: String
        var best: Double
        var laps: Int
        var distance: Double?
        var corners: [CornerRecord] = []
    }

    /// A catalogue id for Sonoma; anything else is a club circuit known by its track name.
    func session(_ spec: Spec) -> LogbookEntry {
        let known = spec.circuit.hasPrefix("Q")
        return LogbookEntry(
            file: .init(path: "/d/\(spec.hash).csv", contentHash: spec.hash, byteCount: 1, importerID: "x"),
            circuitID: known ? spec.circuit : nil, trackName: known ? nil : spec.circuit,
            date: ProjectDetails.day(spec.day),
            car: spec.car,
            laps: (1...spec.laps).map { .init(number: $0, seconds: spec.best + Double($0), isComplete: true) },
            bestLap: spec.best, bestLapNumber: 1, distanceMeters: spec.distance, corners: spec.corners)
    }

    func corner(_ label: String, time: Double) -> CornerRecord {
        CornerRecord(index: 0, label: label, brakePointMeters: 100, minimumSpeed: 20, exitSpeed: 30, timeInCorner: time)
    }

    @Test func aYearIsCountedAndItsBestsAndCornersFound() {
        let sonoma = "Q112563"
        let entries = [
            session(
                Spec(
                    hash: "a", circuit: sonoma, day: "2026-04-12", car: "Miata", best: 118.0, laps: 10,
                    distance: 25_000,
                    corners: [corner("4", time: 9.0), corner("7", time: 7.0)])),
            session(
                Spec(
                    hash: "b", circuit: sonoma, day: "2026-04-12", car: "Miata", best: 117.2, laps: 8, distance: 20_000)
            ),
            session(
                Spec(
                    hash: "c", circuit: sonoma, day: "2026-08-23", car: "Miata", best: 116.9, laps: 12,
                    distance: 30_000,
                    corners: [corner("4", time: 8.6), corner("7", time: 7.3)])),
            session(Spec(hash: "d", circuit: "Thunderhill", day: "2026-06-01", car: "GR86", best: 125.0, laps: 9)),
            session(Spec(hash: "e", circuit: sonoma, day: "2025-10-01", car: "Miata", best: 119.0, laps: 6)),
        ]
        #expect(SeasonSummary.years(in: entries) == [2026, 2025])
        var plan = TrackDefinition(circuitID: "Q112563", name: "Sonoma Raceway", latitude: 38, longitude: -122)
        plan.plan = NextSessionPlan(experiments: [PlannedExperiment(cornerLabel: "4", text: "Brake later.")])
        let elsewhere = TrackDefinition(
            circuitID: "Q999", name: "Elsewhere", latitude: 0, longitude: 0, plan: plan.plan)
        let season = SeasonSummary.make(entries: entries, year: 2026, plans: [plan, elsewhere])
        #expect(season.trackDays == 3 && season.sessions == 4 && season.laps == 39)
        #expect(season.distanceMeters == 75_000)
        #expect(season.personalBestsSet == 4, "every 2026 session bettered what came before it or was a first")
        #expect(season.circuitBests.map(\.title) == ["Sonoma Raceway", "Thunderhill"])
        #expect(season.circuitBests[0].best == 116.9 && season.circuitBests[0].visits == 3)
        #expect(season.circuitBests[0].isNewPersonalBest)
        #expect(season.mostImproved?.label == "4" && abs((season.mostImproved?.change ?? 0) + 0.4) < 0.001)
        #expect(season.mostCostly?.label == "7")
        #expect(season.openPlans.map(\.circuitTitle) == ["Sonoma Raceway"], "an unvisited circuit's plan stays out")
        #expect(season.openPlans[0].experiments == ["Turn 4: Brake later."])
        #expect(season.lines[0] == "3 track days, 4 sessions, 39 laps")
        #expect(season.lines[1] == "75 km driven")
        #expect(season.title == "Season 2026")
        // Narrowed to a car, and a year with nothing.
        let gr86 = SeasonSummary.make(entries: entries, year: 2026, car: "GR86")
        #expect(gr86.sessions == 1 && gr86.circuitBests.first?.title == "Thunderhill")
        #expect(gr86.title == "2026 in the GR86")
        let empty = SeasonSummary.make(entries: entries, year: 2024)
        #expect(empty.sessions == 0 && empty.circuitBests.isEmpty && empty.distanceMeters == nil)
    }
}
