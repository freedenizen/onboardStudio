import Foundation
import Importers
import ProjectModel
import TelemetryKit
import Testing

@testable import MediaKit

/// #456: a chosen day took every file it was given, whatever the file said. A file dated another
/// day, or lying at another circuit, is now read and kept back until it is told where it goes.
@Suite("Files that are not from the chosen day (#456)", .serialized)
struct TrackDayStraysTests {
    static let fixtures = TrackDayImportTests.fixtures

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "strays-\(UUID().uuidString)"))
    }

    func fixture(_ name: String) -> URL { Self.fixtures.appending(path: name) }

    /// A day long before any fixture was written, begun with a car, a driver and the weather.
    func aDayInThePast(in logbook: Logbook, circuitID: String? = nil) throws -> TrackDay {
        var day = TrackDay(
            date: Date(timeIntervalSince1970: 1_700_000_000), circuitID: circuitID,
            trackName: circuitID == nil ? "Fixtures" : nil, car: "GR86", driver: "Sam")
        day.conditions = SessionConditions(weather: .rain, track: .wet)
        try logbook.saveDay(day)
        return day
    }

    func waiting(in reports: [TrackDayImport.Report]) -> [TrackDayImport.Stray] {
        reports.compactMap { if case .waiting(let stray) = $0.outcome { stray } else { nil } }
    }

    @Test func aFileDatedAnotherDayIsKeptBackAndTheRestGoOnTheDay() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = try aDayInThePast(in: logbook)
        // One fixture with a date of its own, one with none.
        let reports = await TrackDayImport.run(
            [fixture("racechrono-v3.csv"), fixture("coaching-laps.csv")], into: logbook, day: day, strays: .kept)
        let lines = reports.map(\.line)
        let dated = try #require(reports.first { $0.url.lastPathComponent == "racechrono-v3.csv" })
        guard case .waiting(let stray) = dated.outcome else {
            Issue.record("the dated file was not kept back: \(lines)")
            return
        }
        #expect(dated.isWaiting && !dated.isAdded && !dated.isAlreadyThere && !dated.isClip)
        #expect(!stray.isClip && stray.date != nil && stray.circuit == nil)
        #expect(stray.reason.hasPrefix("dated ") && stray.reason.hasSuffix(", not this day's date"), "\(stray.reason)")
        #expect(dated.line == "racechrono-v3.csv — not added yet: \(stray.reason)")
        // The file with no date does not say it is another day's: onto the day, as before.
        let undated = try #require(reports.first { $0.url.lastPathComponent == "coaching-laps.csv" })
        guard case .added(let entry) = undated.outcome else {
            Issue.record("the undated file was not added: \(lines)")
            return
        }
        #expect(entry.trackDayID == day.id && entry.car == "GR86")
        // The day's circuit was typed, and the file names none: it takes the day's name (#455),
        // where it used to be listed under a circuit named after the file.
        #expect(entry.trackName == "Fixtures" && LogbookFilter.circuitKey(of: entry) == "Fixtures")
        #expect(undated.notes == ["no circuit recognised in the file, so the day's"], "\(undated.line)")
        // Nothing of the file that waits is in the logbook: no session, no day made for it.
        #expect(logbook.entries().map(\.id) == [entry.id])
        #expect(logbook.days().map(\.id) == [day.id])
    }

    @Test func toldToItGoesOnTheDayItsOwnDateSays() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = try aDayInThePast(in: logbook)
        let strays = waiting(
            in: await TrackDayImport.run([fixture("racechrono-v3.csv")], into: logbook, day: day, strays: .kept))
        #expect(strays.count == 1)

        let placed = TrackDayImport.place(strays, onto: nil, into: logbook)
        let report = try #require(placed.first)
        guard case .added(let entry) = report.outcome else {
            Issue.record("not added: \(report.line)")
            return
        }
        // As Add Files files it with no day chosen: its own day, none of the chosen day's details.
        let own = try #require(entry.trackDayID.flatMap { logbook.day(id: $0) })
        #expect(own.id != day.id)
        #expect(own.date == TrackDay.startOfDay(try #require(entry.date)))
        #expect(entry.car.isEmpty && entry.driver != "Sam" && entry.conditions.isEmpty)
        #expect(report.dayLabel == own.label && report.line.hasSuffix(", in \(own.label)"), "\(report.line)")
        #expect(report.notes.isEmpty)
        #expect(logbook.days().count == 2 && logbook.sessions(of: day).isEmpty)
    }

    @Test func toldToItGoesOnTheChosenDayInSpiteOfItsDate() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = try aDayInThePast(in: logbook)
        let strays = waiting(
            in: await TrackDayImport.run([fixture("racechrono-v3.csv")], into: logbook, day: day, strays: .kept))

        let placed = TrackDayImport.place(strays, onto: day, into: logbook)
        let report = try #require(placed.first)
        guard case .added(let entry) = report.outcome else {
            Issue.record("not added: \(report.line)")
            return
        }
        #expect(entry.trackDayID == day.id && entry.car == "GR86" && entry.driver == "Sam")
        #expect(entry.conditions.weather == .rain)
        // The line says the day's date was not the file's.
        #expect(report.notes == ["dated another day than this one"])
        #expect(report.line.hasSuffix(" (dated another day than this one)"), "\(report.line)")
        #expect(logbook.days().count == 1 && logbook.sessions(of: day).count == 1)
        // Placed twice — the same bytes offered again — it is the session already there.
        let again = TrackDayImport.place(strays, onto: nil, into: logbook)
        #expect(again.first?.isAlreadyThere == true, "\(again.map(\.line))")
        #expect(logbook.entries().count == 1 && logbook.days().count == 1)
    }

    @Test func aFileOfTheDayIsNotAskedAbout() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        // The day the fixture says it was driven, in this machine's calendar.
        let session = try FormatDetector.importSession(at: fixture("racechrono-v3.csv"))
        let day = TrackDay(date: try #require(session.info.createdAt), trackName: "Test Circuit")
        try logbook.saveDay(day)
        let reports = await TrackDayImport.run([fixture("racechrono-v3.csv")], into: logbook, day: day, strays: .kept)
        let report = try #require(reports.first)
        #expect(report.isAdded && report.notes.isEmpty, "\(report.line)")
        #expect(logbook.sessions(of: day).count == 1)
    }

    @Test func aFileWithNoCircuitTakesTheDaysAndTheLineSaysSo() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let sonoma = try #require(CircuitCatalog.all.first { $0.name == "Sonoma Raceway" })
        let day = try aDayInThePast(in: logbook, circuitID: sonoma.id)
        // No date and no circuit in the file: a log without GPS recorded that day belongs on it.
        let reports = await TrackDayImport.run([fixture("coaching-laps.csv")], into: logbook, day: day, strays: .kept)
        let report = try #require(reports.first)
        guard case .added(let entry) = report.outcome else {
            Issue.record("not added: \(report.line)")
            return
        }
        #expect(entry.circuitID == sonoma.id && entry.trackDayID == day.id)
        #expect(report.notes == ["no circuit recognised in the file, so the day's"])
        #expect(report.line.hasSuffix(" (no circuit recognised in the file, so the day's)"), "\(report.line)")
    }

    @Test func aFileAtAnotherCircuitIsKeptBack() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let sonoma = try #require(CircuitCatalog.all.first { $0.name == "Sonoma Raceway" })
        let day = try aDayInThePast(in: logbook, circuitID: sonoma.id)
        // A fixture with no date whose trace lies at a circuit of the catalogue, and not the day's.
        let reports = await TrackDayImport.run([fixture("vbox-canbus.vbo")], into: logbook, day: day, strays: .kept)
        let stray = try #require(waiting(in: reports).first, "\(reports.map(\.line))")
        let there = try #require(stray.circuit)
        #expect(stray.date == nil && there != sonoma.name)
        #expect(stray.reason == "at \(there), not this day's circuit")
        #expect(logbook.entries().isEmpty)

        // On its own day it keeps the circuit it lies at, not the chosen day's.
        let placed = TrackDayImport.place([stray], onto: nil, into: logbook)
        guard case .added(let entry) = try #require(placed.first).outcome else { return }
        #expect(entry.title == there && entry.trackDayID != day.id)

        // A day whose circuit was typed cannot be compared: the file goes on it unasked.
        let other = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: other.directory) }
        let typed = try aDayInThePast(in: other)
        let unasked = await TrackDayImport.run([fixture("vbox-canbus.vbo")], into: other, day: typed, strays: .kept)
        #expect(unasked.first?.isAdded == true, "\(unasked.map(\.line))")
    }

    /// A drive the logbook has from another file is that (#465), whatever day was chosen: there is
    /// nothing to ask about a file that will not be added.
    @Test func aSecondExportOfASessionAlreadyThereIsNotAskedAbout() async throws {
        let logbook = temporaryLogbook()
        let folder = FileManager.default.temporaryDirectory.appending(path: "stray-twin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: logbook.directory)
            try? FileManager.default.removeItem(at: folder)
        }
        _ = await TrackDayImport.run([fixture("racechrono-v2.csv")], into: logbook)
        let twin = folder.appending(path: "session_v3.csv")
        try TrackDayImportTests.v3Twin.write(to: twin, atomically: true, encoding: .utf8)
        let day = try aDayInThePast(in: logbook)
        let reports = await TrackDayImport.run([twin], into: logbook, day: day, strays: .kept)
        #expect(waiting(in: reports).isEmpty && reports.first?.isAlreadyThere == true, "\(reports.map(\.line))")
    }

    @Test func aClipDatedAnotherDayIsKeptBackToo() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = try aDayInThePast(in: logbook)
        // The fixture has no camera clock, so its file's date is its clock — never the day's.
        let reports = await TrackDayImport.run([fixture("test-3s.mp4")], into: logbook, day: day, strays: .kept)
        let stray = try #require(waiting(in: reports).first, "\(reports.map(\.line))")
        #expect(stray.isClip && stray.date != nil)
        #expect(logbook.day(id: day.id)?.clips.isEmpty == true, "nothing on the day before the answer")

        // Onto the day its clock says…
        let own = TrackDayImport.place([stray], onto: nil, into: logbook)
        #expect(own.first?.isClip == true, "\(own.map(\.line))")
        #expect(logbook.day(id: day.id)?.clips.isEmpty == true)
        let made = try #require(logbook.days().first { $0.id != day.id })
        #expect(made.clips.map(\.name) == ["test-3s.mp4"])
        // …and once it is on a day, it is not put on another.
        let again = TrackDayImport.place([stray], onto: day, into: logbook)
        #expect(again.first?.line.hasSuffix("video already on the day") == true, "\(again.map(\.line))")

        // Onto the chosen day, when that is the answer.
        let other = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: other.directory) }
        let chosen = try aDayInThePast(in: other)
        let kept = waiting(
            in: await TrackDayImport.run([fixture("test-3s.mp4")], into: other, day: chosen, strays: .kept))
        _ = TrackDayImport.place(kept, onto: chosen, into: other)
        #expect(other.day(id: chosen.id)?.clips.map(\.name) == ["test-3s.mp4"])
        #expect(other.days().count == 1)
    }

    /// Without the option — the CLI's `--day`, and every caller before #456 — the day takes it all.
    @Test func withoutTheOptionEveryFileStillGoesOnTheChosenDay() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let day = try aDayInThePast(in: logbook)
        let reports = await TrackDayImport.run([fixture("racechrono-v3.csv")], into: logbook, day: day)
        let report = try #require(reports.first)
        #expect(report.isAdded && !report.isWaiting)
        #expect(report.notes == ["dated another day than this one"], "\(report.line)")
        #expect(logbook.sessions(of: day).count == 1)
    }

    @Test func theQuestionCountsTheFilesInItsWords() {
        typealias Stray = TrackDayImport.Stray
        #expect(Stray.headline(3, of: 16, day: "the day") == "3 of these 16 files are not from the day.")
        #expect(Stray.headline(1, of: 16, day: "the day") == "1 of these 16 files is not from the day.")
        #expect(Stray.headline(4, of: 4, day: "the day") == "None of these 4 files is from the day.")
        #expect(Stray.headline(1, of: 1, day: "the day") == "This file is not from the day.")
        #expect(Stray.explanation(1).hasPrefix("It says below what is different. Put it on its own day,"))
        #expect(Stray.explanation(2).hasPrefix("Each says below what is different. Put them on their own days,"))
    }
}
