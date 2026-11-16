import Foundation
import ProjectModel
import Testing

@testable import MediaKit

/// #559: a session added to the Logbook in a car starts with the car's starting setup.
@Suite("The starting setup on import (#559)")
struct TrackDayImportSetupTests {
    static let csv = TrackDayImportTests.fixtures.appending(path: "racerender-basic.csv")

    @Test func aNewSessionInTheCarStartsWithItsStartingSetup() async throws {
        let logbook = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "setup-import-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        var sheet = SetupSheet()
        sheet.camber.frontLeft = -2.5
        let base = try logbook.saveSetup(SavedSetup(name: "Base", tyres: "RE-71RS", sheet: sheet), forCar: "Miata")
        try logbook.setStartingSetup(base.id, forCar: "Miata")
        _ = await TrackDayImport.run([Self.csv], into: logbook, car: "Miata")
        let entry = try #require(logbook.entries().first)
        #expect(entry.conditions.sheet.name == "Base")
        #expect(entry.conditions.sheet.camber.frontLeft == -2.5)
        #expect(entry.conditions.tyres == "RE-71RS")
    }

    @Test func aSessionInAnotherCarStartsWithNone() async throws {
        let logbook = Logbook(
            directory: FileManager.default.temporaryDirectory.appending(path: "setup-import-\(UUID().uuidString)"))
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let base = try logbook.saveSetup(SavedSetup(name: "Base"), forCar: "Miata")
        try logbook.setStartingSetup(base.id, forCar: "Miata")
        _ = await TrackDayImport.run([Self.csv], into: logbook, car: "GR86")
        #expect(try #require(logbook.entries().first).conditions.sheet.isEmpty)
    }
}
