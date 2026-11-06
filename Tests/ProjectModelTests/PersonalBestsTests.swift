import Foundation
import Testing

@testable import ProjectModel

@Suite("Personal bests (#351)")
struct PersonalBestsTests {
    func entry(_ hash: String, circuit: String = "Q112563", car: String, year: Int, best: Double?) -> LogbookEntry {
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 6, day: 1))
        return LogbookEntry(
            file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"), circuitID: circuit,
            date: date, car: car, bestLap: best, bestLapNumber: best.map { _ in 3 })
    }

    var entries: [LogbookEntry] {
        [
            entry("a", car: "Miata", year: 2025, best: 118.0),
            entry("b", car: "Miata", year: 2026, best: 116.9),
            entry("c", car: "GR86", year: 2026, best: 112.4),
            entry("d", car: "Miata", year: 2026, best: 117.5),
            entry("e", circuit: "Thunderhill", car: "Miata", year: 2026, best: 125.0),
            entry("f", car: "Miata", year: 2026, best: nil),
        ]
    }

    @Test func theBestIsAQueryByCircuitCarAndYear() throws {
        let all = entries
        let overall = try #require(PersonalBests.best(in: all, circuitKey: "Q112563"))
        #expect(overall.seconds == 112.4 && overall.car == "GR86" && overall.lapNumber == 3)
        #expect(PersonalBests.best(in: all, circuitKey: "Q112563", car: "miata")?.seconds == 116.9)
        #expect(PersonalBests.best(in: all, circuitKey: "Q112563", car: "Miata", year: 2025)?.seconds == 118.0)
        #expect(PersonalBests.best(in: all, circuitKey: "Thunderhill")?.seconds == 125.0)
        #expect(PersonalBests.best(in: all, circuitKey: "Nowhere") == nil)
        #expect(PersonalBests.visits(in: all, circuitKey: "Q112563") == 5)
    }

    @Test func theSessionsThatSetABestAreBadgedInTheirOrder() {
        let all = entries  // once: every read of `entries` makes fresh ids
        let setters = PersonalBests.entriesSettingBests(in: all)
        let ids = Set(all.filter { ["a", "b", "c"].contains($0.file.contentHash) }.map(\.id))
        let notSetters = Set(all.filter { ["d", "e", "f"].contains($0.file.contentHash) }.map(\.id))
        // a: the first ever; b: quicker than a, same car; c: the other car's first and the overall best;
        // d: slower than b in the same car and slower than c; e: the first at Thunderhill — a PB there.
        #expect(ids.isSubset(of: setters))
        let thunderhill = all.first { $0.file.contentHash == "e" }?.id
        #expect(thunderhill.map { setters.contains($0) } == true)
        #expect(notSetters.subtracting([thunderhill].compactMap { $0 }).isDisjoint(with: setters))
    }

    @Test func theBadgeTellsTheBestNowFromOnesSinceBeaten() {
        func dated(_ hash: String, circuit: String = "Q112563", car: String, day: Int, best: Double) -> LogbookEntry {
            let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 6, day: day))
            return LogbookEntry(
                file: .init(path: "/d/\(hash).csv", contentHash: hash, byteCount: 1, importerID: "x"),
                circuitID: circuit, date: date, car: car, bestLap: best, bestLapNumber: 3)
        }
        // Given out of date order, as an import of a whole folder can be.
        let all = [
            dated("d", car: "Miata", day: 4, best: 117.5),
            dated("a", car: "Miata", day: 1, best: 118.0),
            dated("c", car: "GR86", day: 3, best: 112.4),
            dated("tie", car: "Miata", day: 5, best: 116.9),
            dated("b", car: "Miata", day: 2, best: 116.9),
            dated("e", circuit: "Thunderhill", car: "Miata", day: 6, best: 125.0),
        ]
        let badges = PersonalBests.badges(in: all)
        func badge(_ hash: String) -> PersonalBestBadge? {
            all.first { $0.file.contentHash == hash }.flatMap { badges[$0.id] }
        }
        #expect(badge("a") == .former, "the first ever, beaten in the same car")
        #expect(badge("b") == .current, "beaten overall by the GR86, but still the best in the Miata")
        #expect(badge("c") == .current, "the best at the circuit")
        #expect(badge("d") == nil, "never a best")
        #expect(badge("tie") == nil, "equalling the best does not take it")
        #expect(badge("e") == .current, "the only session at its circuit")
        #expect(PersonalBests.entriesSettingBests(in: all) == Set(badges.keys))
    }

    @Test func theTextKeysNameTheBestInTheCarWhenThereIsOne() {
        let all = entries
        let miata = PersonalBests.detailKeys(in: all, circuitKey: "Q112563", car: "Miata")
        #expect(miata["pb"] == "1:56.90" && miata["pbCar"] == "Miata" && miata["visits"] == "5")
        #expect(miata["pbDate"]?.contains("2026") == true)
        let anyCar = PersonalBests.detailKeys(in: all, circuitKey: "Q112563", car: "")
        #expect(anyCar["pb"] == "1:52.40" && anyCar["pbCar"] == "GR86")
        let unknownCar = PersonalBests.detailKeys(in: all, circuitKey: "Q112563", car: "Elise")
        #expect(unknownCar["pb"] == "1:52.40", "a car the logbook has not seen falls back to the overall best")
        #expect(PersonalBests.detailKeys(in: all, circuitKey: "Nowhere", car: nil) == ["visits": "0"])
        // Filling text: a typed detail of the same name still wins.
        var details = ProjectDetails()
        details.extras = [ProjectDetail(name: "pb", value: "typed")]
        let filled = details.adding(miata)
        #expect(filled.fill("{pb} after {visits} visits, best {pbCar}") == "typed after 5 visits, best Miata")
        // A timer against the personal best, or text naming it, asks the compile for the logbook.
        var project = Project(displayObjects: [
            DisplayObject(label: "T", inputID: nil, frame: .full, kind: .text(TextParams(text: "PB {pb}")))
        ])
        #expect(project.usesLogbookKeys && !project.needsPersonalBest)
        project.displayObjects = [
            DisplayObject(
                label: "D", inputID: nil, frame: .full,
                kind: .timer(TimerParams(mode: .deltaToBest, deltaReference: .personalBest)))
        ]
        #expect(project.needsPersonalBest && !project.usesLogbookKeys)
        #expect(!Project().needsPersonalBest)
    }
}
