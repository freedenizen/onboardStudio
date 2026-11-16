import Foundation
import Testing

@testable import ProjectModel

/// #559: what was on the car, value by value, and the setups a car keeps.
@Suite("Setup sheets (#559)")
struct SetupSheetTests {
    static let psi = SetupUnits(pressure: .psi, length: .inches)
    static let bar = SetupUnits(pressure: .bar, length: .millimeters)

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "setups-\(UUID().uuidString)"))
    }

    static func sheet(cold: Double, rear: Double? = nil) -> SetupSheet {
        var sheet = SetupSheet()
        for corner in SetupItem.Corner.allCases {
            let value = corner.rawValue < 2 ? cold : rear ?? cold
            SetupItem.coldPressure(corner).set(SetupItem.format(value, 1), in: &sheet, units: Self.psi)
        }
        return sheet
    }

    // MARK: - Values

    @Test func aPressureTypedInPsiReadsBackAsTypedAndInBar() {
        var sheet = SetupSheet()
        #expect(SetupItem.coldPressure(.frontLeft).set("30.5", in: &sheet, units: Self.psi))
        #expect(SetupItem.coldPressure(.frontLeft).text(in: sheet, units: Self.psi) == "30.5 psi")
        #expect(SetupItem.coldPressure(.frontLeft).text(in: sheet, units: Self.bar) == "2.1 bar")
        #expect(SetupItem.coldPressure(.frontLeft).editText(in: sheet, units: Self.psi) == "30.5")
    }

    @Test func theSamePressureTypedTwiceIsTheSameValue() {
        var once = SetupSheet()
        var twice = SetupSheet()
        SetupItem.coldPressure(.rearLeft).set("28", in: &once, units: Self.psi)
        SetupItem.coldPressure(.rearLeft).set("28.0", in: &twice, units: Self.psi)
        #expect(once == twice)
        #expect(SetupItem.coldPressure(.rearLeft).key(in: once) == SetupItem.coldPressure(.rearLeft).key(in: twice))
    }

    @Test func notANumberIsRefusedAndEmptyClears() {
        var sheet = SetupSheet()
        SetupItem.camber(.frontLeft).set("-2,5", in: &sheet, units: Self.bar)
        #expect(sheet.camber.frontLeft == -2.5)
        #expect(SetupItem.camber(.frontLeft).text(in: sheet, units: Self.bar) == "−2.5°")
        #expect(!SetupItem.camber(.frontLeft).set("lots", in: &sheet, units: Self.bar))
        #expect(sheet.camber.frontLeft == -2.5)
        SetupItem.camber(.frontLeft).set("", in: &sheet, units: Self.bar)
        #expect(sheet.hasNoValues)
    }

    @Test func rideHeightsAreKeptInMillimetres() {
        var sheet = SetupSheet()
        SetupItem.rideHeight(.front).set("4.5", in: &sheet, units: Self.psi)
        #expect(sheet.rideHeight.front == 114.3)
        #expect(SetupItem.rideHeight(.front).text(in: sheet, units: Self.bar) == "114 mm")
        #expect(SetupItem.bump(.rear).set("1", in: &sheet, units: Self.bar))
        #expect(SetupItem.bump(.rear).text(in: sheet, units: Self.bar) == "1 click")
    }

    @Test func theSummarySaysTheNameTheColdPressuresAndHowMuchElse() {
        var sheet = Self.sheet(cold: 30, rear: 28)
        sheet.name = "Base"
        sheet.camber.frontLeft = -2.5
        sheet.wing = "Flat"
        #expect(sheet.summary(units: Self.psi) == "Base · 30/28 psi cold · 2 more")
        sheet.coldPressure.frontRight = nil
        #expect(sheet.summary(units: Self.psi).hasPrefix("Base · 30/–/28/28 psi cold"))
        #expect(SetupSheet().summary(units: Self.psi).isEmpty)
    }

    // MARK: - On disk

    @Test func conditionsWithoutASheetReadAndWriteAsBefore() throws {
        let old = Data(#"{"tyres":"RE-71RS","setup":"soft rear"}"#.utf8)
        let conditions = try JSONDecoder().decode(SessionConditions.self, from: old)
        #expect(conditions.sheet.isEmpty)
        #expect(conditions.tyres == "RE-71RS" && conditions.setup == "soft rear")
        let written = try #require(String(bytes: JSONEncoder().encode(conditions), encoding: .utf8))
        #expect(!written.contains("sheet"))
        var noted = conditions
        noted.sheet = Self.sheet(cold: 30)
        let again = try JSONDecoder().decode(SessionConditions.self, from: JSONEncoder().encode(noted))
        #expect(again == noted)
    }

    @Test func aToeUnitALaterBuildAddsReadsAsMillimetres() throws {
        let json = Data(#"{"toe":{"front":1},"toeUnit":"arcminutes"}"#.utf8)
        let sheet = try JSONDecoder().decode(SetupSheet.self, from: json)
        #expect(sheet.toe.front == 1 && sheet.toeUnit == .millimeters)
    }

    // MARK: - Kept with the car

    @Test func aSetupSavedUnderANameTheCarUsesReplacesIt() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let base = try logbook.saveSetup(SavedSetup(name: "Base", sheet: Self.sheet(cold: 30)), forCar: "Miata")
        #expect(base.sheet.name == "Base")
        try logbook.saveSetup(
            SavedSetup(name: " base ", tyres: "RE-71RS", sheet: Self.sheet(cold: 29)), forCar: "miata")
        let car = try #require(logbook.cars().first)
        #expect(logbook.cars().count == 1)
        #expect(car.setups.count == 1)
        #expect(car.setups.first?.id == base.id)
        #expect(car.setups.first?.tyres == "RE-71RS")
    }

    @Test func theStartingSetupGoesOnlyOntoASessionWithNone() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let base = try logbook.saveSetup(
            SavedSetup(name: "Base", tyres: "RE-71RS", sheet: Self.sheet(cold: 30)), forCar: "Miata")
        var bare = SessionConditions()
        logbook.applyStartingSetup(to: &bare, car: "Miata")
        #expect(bare.sheet.isEmpty, "no starting setup chosen yet")
        try logbook.setStartingSetup(base.id, forCar: "Miata")
        logbook.applyStartingSetup(to: &bare, car: "Miata")
        #expect(bare.sheet.name == "Base" && bare.tyres == "RE-71RS")
        var own = SessionConditions(tyres: "Old set")
        logbook.applyStartingSetup(to: &own, car: "Miata")
        #expect(own.sheet.isEmpty && own.tyres == "Old set")
        var otherCar = SessionConditions()
        logbook.applyStartingSetup(to: &otherCar, car: "GR86")
        #expect(otherCar.isEmpty)
    }

    @Test func deletingTheStartingSetupLeavesNone() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let base = try logbook.saveSetup(SavedSetup(name: "Base", sheet: Self.sheet(cold: 30)), forCar: "Miata")
        try logbook.setStartingSetup(base.id, forCar: "Miata")
        try logbook.deleteSetup(base.id, forCar: "Miata")
        let car = try #require(logbook.cars().first)
        #expect(car.setups.isEmpty && car.startingSetupID == nil)
    }

    @Test func aCarKeptForItsSetupsIsNotTidiedAway() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        try logbook.saveSetup(SavedSetup(name: "Base"), forCar: "Miata")
        try logbook.tidyGarage()
        #expect(logbook.cars().map(\.name) == ["Miata"])
    }

    @Test func twoCarsMadeOneKeepBothCarsSetups() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        try logbook.saveSetup(SavedSetup(name: "Base"), forCar: "MX-5")
        let wet = try logbook.saveSetup(SavedSetup(name: "Wet"), forCar: "Miata")
        try logbook.setStartingSetup(wet.id, forCar: "Miata")
        try logbook.renameCar("Miata", to: "mx-5")
        let car = try #require(logbook.cars().first)
        #expect(logbook.cars().count == 1)
        #expect(car.setups.map(\.name) == ["Base", "Wet"])
        #expect(car.startingSetup?.name == "Wet")
    }

    @Test func aCarSetOnADayGivesItsSessionsTheStartingSetup() throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let base = try logbook.saveSetup(SavedSetup(name: "Base", sheet: Self.sheet(cold: 30)), forCar: "Miata")
        try logbook.setStartingSetup(base.id, forCar: "Miata")
        let day = TrackDay(date: GarageTests.date(9, 20), trackName: "Stadium")
        try logbook.saveDay(day)
        try logbook.save(GarageTests.entry("a", car: "", day: day))
        try logbook.setCar("Miata", onDays: [day.id])
        #expect(logbook.entries().first?.conditions.sheet.name == "Base")
    }

    // MARK: - Undo

    @Test func aChangeOfSetupIsNamedSo() {
        let entry = LogbookEntry(file: .init(path: "/s.csv", contentHash: "s", byteCount: 1, importerID: "x"))
        var changed = entry
        changed.conditions.sheet = Self.sheet(cold: 30)
        changed.conditions.tyres = "New set"
        #expect(LogbookEditName.of(entry, changed) == "Change Setup")
        changed.conditions.weather = .rain
        #expect(LogbookEditName.of(entry, changed) == "Change Conditions")
    }
}
