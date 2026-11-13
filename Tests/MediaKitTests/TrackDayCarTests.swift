import Foundation
import ProjectModel
import Testing

@testable import MediaKit

/// #489: what car the sessions of a files-first import arrive with.
@Suite("The car of an import (#489)", .serialized)
struct TrackDayCarTests {
    static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "trackday-car-\(UUID().uuidString)"))
    }

    /// A first import has no earlier session to take a car from: every day it made is one the
    /// report asks about, and the car given there reaches all of their sessions.
    @Test func aFirstImportLeavesItsDaysForTheReportToAsk() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let reports = await TrackDayImport.run([Self.fixtures], into: logbook)
        let added = Set(
            reports.compactMap { report -> UUID? in
                if case .added(let entry) = report.outcome { entry.id } else { nil }
            })
        #expect(!added.isEmpty)
        #expect(logbook.entries().allSatisfy { $0.car.isEmpty })
        let carless = Garage.daysWithoutCar(added: added, entries: logbook.entries(), days: logbook.days())
        #expect(Set(carless.map(\.id)) == Set(logbook.entries().compactMap(\.trackDayID)))
        try logbook.setCar("Miata", onDays: carless.map(\.id))
        #expect(logbook.entries().allSatisfy { $0.car == "Miata" })
        #expect(Garage.daysWithoutCar(added: added, entries: logbook.entries(), days: logbook.days()).isEmpty)
    }

    /// A session added with no day chosen goes on the day its date and circuit say; when that day
    /// names a car, the session is that car's — not the car of whichever session came before at the
    /// circuit, or none.
    @Test func aSessionJoiningADayThatNamesACarTakesIt() async throws {
        let file = Self.fixtures.appending(path: "coaching-laps.csv")
        // The day the file goes on, as an empty logbook makes it.
        let scratch = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: scratch.directory) }
        _ = await TrackDayImport.run([file], into: scratch)
        var day = try #require(scratch.days().first)
        day.car = "Miata"

        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        try logbook.saveDay(day)
        let reports = await TrackDayImport.run([file], into: logbook)
        let report = try #require(reports.first { $0.isAdded }, "\(reports.map(\.line))")
        guard case .added(let entry) = report.outcome else { return }
        #expect(entry.trackDayID == day.id)
        #expect(entry.car == "Miata")
        // A car given for the whole batch still wins.
        let other = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: other.directory) }
        try other.saveDay(day)
        let given = await TrackDayImport.run([file], into: other, car: "GR86")
        guard case .added(let mine) = try #require(given.first { $0.isAdded }).outcome else { return }
        #expect(mine.car == "GR86")
    }
}
