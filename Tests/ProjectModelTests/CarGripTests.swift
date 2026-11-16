import Foundation
import Testing

@testable import ProjectModel
@testable import TelemetryKit

/// #558: the grip a car has shown in conditions like a session's.
@Suite("A car's grip by conditions (#558)")
struct CarGripTests {
    static func entry(
        _ hash: String, car: String = "Miata", grip: Double?, surface: SessionConditions.Track? = .dry,
        tyres: String = "", air: Double? = nil
    ) -> LogbookEntry {
        var entry = GarageTests.entry(hash, car: car)
        entry.conditions = SessionConditions(track: surface, ambientCelsius: air, tyres: tyres)
        entry.grip = grip.map { GripRecord(envelope: GripEnvelope(circle: $0), bestLap: nil) }
        return entry
    }

    @Test func theLimitIsTheBestOfTheCarsSessionsOnTheSameSurface() throws {
        let today = Self.entry("a", grip: 0.9)
        let entries = [
            today, Self.entry("b", grip: 1.0), Self.entry("c", grip: 1.2),
            Self.entry("wet", grip: 0.7, surface: .wet), Self.entry("other", car: "GR86", grip: 1.4),
        ]
        let limit = try #require(CarGrip.limit(for: today, among: entries))
        #expect(limit.sessions == 3)
        #expect(limit.best.peak == 1.2 && limit.typical.peak == 1.0)
        #expect(limit.basis == ["dry"])
        #expect(limit.summary == "1.00–1.20 G from 3 sessions, dry")
    }

    @Test func aWetSessionIsReadAgainstWetGrip() throws {
        let wet = Self.entry("w1", grip: 0.6, surface: .damp)
        let entries = [wet, Self.entry("w2", grip: 0.7, surface: .wet), Self.entry("dry", grip: 1.2)]
        let limit = try #require(CarGrip.limit(for: wet, among: entries))
        #expect(limit.best.peak == 0.7 && limit.basis == ["wet"])
    }

    @Test func tyresAndAirNarrowItWhenThereAreSessionsEnough() throws {
        let today = Self.entry("a", grip: 1.0, tyres: "RE-71RS", air: 20)
        let entries = [
            today, Self.entry("b", grip: 1.05, tyres: "re-71rs", air: 24),
            Self.entry("hot", grip: 0.95, tyres: "RE-71RS", air: 35), Self.entry("slicks", grip: 1.4, tyres: "Slicks"),
        ]
        let limit = try #require(CarGrip.limit(for: today, among: entries))
        #expect(limit.sessions == 2)
        #expect(limit.basis == ["dry", "RE-71RS", "12–28 °C"])
    }

    @Test func tooFewAlikeLetsTheAirThenTheTyresGo() throws {
        let today = Self.entry("a", grip: 1.0, tyres: "New", air: 20)
        let air = try #require(
            CarGrip.limit(for: today, among: [today, Self.entry("b", grip: 1.1, tyres: "New", air: 40)]))
        #expect(air.basis == ["dry", "New"] && air.sessions == 2)
        let tyres = try #require(
            CarGrip.limit(for: today, among: [today, Self.entry("b", grip: 1.1, tyres: "Old", air: 40)]))
        #expect(tyres.basis == ["dry"] && tyres.sessions == 2)
    }

    @Test func theDriversAdjustmentScalesIt() throws {
        let today = Self.entry("a", grip: 1.0)
        let limit = try #require(CarGrip.limit(for: today, among: [today], adjustment: 1.1))
        #expect(abs(limit.limit.peak - 1.1) < 1e-9)
        #expect(CarGrip.limit(for: Self.entry("none", grip: nil), among: []) == nil)
    }

    @Test func theAdjustmentIsKeptWithTheCar() throws {
        let logbook = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "grip-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        try logbook.setGripAdjustment(5, forCar: "Miata")
        #expect(logbook.cars().first?.gripAdjustment == 2, "kept within twice")
        try logbook.tidyGarage()
        #expect(logbook.cars().count == 1, "a car with an adjustment is kept")
        let entry = Self.entry("a", grip: 1)
        try logbook.save(entry)
        #expect(abs((logbook.gripLimit(for: entry)?.limit.peak ?? 0) - 2) < 1e-9)
    }

    @Test func anEntryFromBeforeIsOfferedAReading() throws {
        let entry = LogbookEntry(file: .init(path: "/a.csv", contentHash: "a", byteCount: 1, importerID: "x"))
        let again = try JSONDecoder().decode(LogbookEntry.self, from: JSONEncoder().encode(entry))
        #expect(again.needsGripReading && again.grip == nil)
    }
}

@Suite("Grip in words (#558)")
struct GripWordingTests {
    static func use(gaps: [Double?]) -> GripUse {
        GripUse(
            meanUsed: 0.82, nearLimit: 0.14, coastingSeconds: 3.24, roughness: 1,
            corners: gaps.enumerated().map { index, lowest in
                GripUse.Corner(
                    index: index, label: String(index + 1), meanUsed: 0.8, peakUsed: 1, nearLimit: 0.2,
                    gap: lowest.map { GripUse.Gap(lowestUsed: $0, lowestG: $0, seconds: 0.4, at: 100) })
            })
    }

    @Test func whatADriverReads() {
        let use = Self.use(gaps: [0.3, 0.9, nil, 0.2])
        #expect(
            GripWording.measurements(use)
                == "Used 82% of the grip braking and turning · 14% of the lap near the limit · 3.2 s coasting")
        #expect(GripWording.gaps(use) == "Braking stopped before turning into Turns 1 and 4.")
        #expect(GripWording.gaps(Self.use(gaps: [0.7])) == nil)
        #expect(GripWording.gaps(Self.use(gaps: [0.1])) == "Braking stopped before turning into Turn 1.")
    }
}
