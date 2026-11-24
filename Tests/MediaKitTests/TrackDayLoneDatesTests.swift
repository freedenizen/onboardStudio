import Foundation
import ProjectModel
import Testing

@testable import MediaKit

/// #655: with no day chosen, each file went on the day its own date said, so a recording from a
/// camera whose clock was wrong became a session on a track day of its own, without a word. A
/// file dated away from the rest of what it was added with now waits to be asked about.
@Suite("A file dated away from the rest (#655)", .serialized)
struct TrackDayLoneDatesTests {
    /// Three fixtures dated one day at one circuit, and fixtures dated other days.
    static let sameDay = ["racechrono-v2.csv", "session.vbo", "track.nmea"]
    static let another = "racechrono-v3.csv"

    func temporaryLogbook() -> Logbook {
        Logbook(directory: FileManager.default.temporaryDirectory.appending(path: "lone-\(UUID().uuidString)"))
    }

    func fixtures(_ names: [String]) -> [URL] { names.map { TrackDayImportTests.fixtures.appending(path: $0) } }

    func waiting(in reports: [TrackDayImport.Report]) -> [TrackDayImport.Stray] {
        reports.compactMap { if case .waiting(let stray) = $0.outcome { stray } else { nil } }
    }

    func added(in reports: [TrackDayImport.Report]) -> [LogbookEntry] {
        reports.compactMap { if case .added(let entry) = $0.outcome { entry } else { nil } }
    }

    @Test("The one file of another date waits, and nothing is made for it")
    func theLoneFileWaits() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let reports = await TrackDayImport.run(
            fixtures(Self.sameDay + [Self.another]), into: logbook, strays: .kept)
        #expect(reports.count == 4, "\(reports.map(\.line))")
        // A line for each file, in the order the files are read.
        #expect(reports.map(\.url.lastPathComponent) == (Self.sameDay + [Self.another]).sorted())
        let sessions = added(in: reports)
        #expect(sessions.count == 3, "\(reports.map(\.line))")
        let day = try #require(Set(sessions.compactMap(\.trackDayID)).first.flatMap { logbook.day(id: $0) })
        #expect(Set(sessions.compactMap(\.trackDayID)).count == 1)

        let stray = try #require(waiting(in: reports).first)
        #expect(waiting(in: reports).count == 1)
        #expect(stray.url.lastPathComponent == Self.another && !stray.isClip)
        // It is asked about against the day the others went on.
        #expect(stray.rest?.id == day.id)
        #expect(stray.reason.hasPrefix("dated ") && stray.reason.hasSuffix(", not the date of the other files"))
        let line = try #require(reports.first { $0.isWaiting }).line
        #expect(line == "\(Self.another) — not added yet: \(stray.reason)")
        // Nothing of it is in the logbook: no session, and no track day of its own.
        #expect(logbook.entries().count == 3)
        #expect(logbook.days().map(\.id) == [day.id])
    }

    @Test("Told to, it goes on the day of the others, or on its own")
    func theAnswers() async throws {
        for ontoTheRest in [true, false] {
            let logbook = temporaryLogbook()
            defer { try? FileManager.default.removeItem(at: logbook.directory) }
            let reports = await TrackDayImport.run(
                fixtures(Self.sameDay + [Self.another]), into: logbook, strays: .kept)
            let strays = waiting(in: reports)
            let rest = try #require(strays.first?.rest)
            let placed = TrackDayImport.place(strays, onto: ontoTheRest ? rest : nil, into: logbook)
            let entry = try #require(added(in: placed).first, "\(placed.map(\.line))")
            if ontoTheRest {
                #expect(entry.trackDayID == rest.id)
                #expect(logbook.days().count == 1)
                #expect(placed.first?.notes == ["dated another day than this one"])
            } else {
                #expect(entry.trackDayID != rest.id)
                #expect(logbook.days().count == 2)
                #expect(placed.first?.dayLabel != nil)
            }
        }
    }

    @Test("The file that waits can be the first one read")
    func theLoneFileComesFirst() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        // "activity.tcx" sorts before the three that share a day.
        let reports = await TrackDayImport.run(
            fixtures(["activity.tcx"] + Self.sameDay), into: logbook, strays: .kept)
        #expect(reports.first?.url.lastPathComponent == "activity.tcx")
        #expect(reports.first?.isWaiting == true, "\(reports.map(\.line))")
        #expect(added(in: reports).count == 3 && logbook.days().count == 1)
    }

    @Test("A folder of several days is filed as it always was")
    func severalDaysAreNotAskedAbout() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        // Two days with two files each, and one file alone: there is no one day it could be of.
        let names = ["racechrono-v2.csv", "session.vbo", "activity.tcx", "track.gpx", Self.another]
        let reports = await TrackDayImport.run(fixtures(names), into: logbook, strays: .kept)
        #expect(waiting(in: reports).isEmpty, "\(reports.map(\.line))")
        #expect(added(in: reports).count == 5)
        #expect(Set(added(in: reports).compactMap(\.trackDayID)).count == 3)
    }

    @Test("Two files of two dates are two days, unasked")
    func twoFilesOfTwoDates() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let reports = await TrackDayImport.run(
            fixtures(["racechrono-v2.csv", Self.another]), into: logbook, strays: .kept)
        #expect(waiting(in: reports).isEmpty && added(in: reports).count == 2 && logbook.days().count == 2)
    }

    @Test("A file dated a day the logbook already has is that day's")
    func aDayAlreadyInTheLogbook() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        // The day of the file that would otherwise be alone, begun beforehand.
        let alone = await TrackDayImport.run(fixtures([Self.another]), into: TemporaryLogbook.shared, strays: .kept)
        let date = try #require(added(in: alone).first?.date)
        try logbook.saveDay(TrackDay(date: TrackDay.startOfDay(date), trackName: "Begun Before"))
        let reports = await TrackDayImport.run(
            fixtures(Self.sameDay + [Self.another]), into: logbook, strays: .kept)
        #expect(waiting(in: reports).isEmpty, "\(reports.map(\.line))")
        #expect(added(in: reports).count == 4)
    }

    @Test("The command line, which cannot ask, files each on its own day")
    func withoutKeepingBack() async throws {
        let logbook = temporaryLogbook()
        defer { try? FileManager.default.removeItem(at: logbook.directory) }
        let reports = await TrackDayImport.run(fixtures(Self.sameDay + [Self.another]), into: logbook)
        #expect(waiting(in: reports).isEmpty && added(in: reports).count == 4 && logbook.days().count == 2)
    }

    @Test("The question names the day of the others and what the buttons do")
    func wording() {
        typealias Stray = TrackDayImport.Stray
        #expect(Stray.addTitle(chosen: true) == "Add to This Day")
        #expect(Stray.addTitle(chosen: false) == "Add to That Day")
        #expect(Stray.explanation(1, chosen: false).contains("add it to the day of the other files"))
        #expect(Stray.explanation(2, chosen: false).contains("add them to the day of the other files"))
        #expect(Stray.explanation(1).contains("add it to this day anyway"))
        #expect(Stray.addHelp(chosen: false).hasSuffix("the day of the other files decides"))
    }
}

/// A scratch logbook for reading a fixture's date, emptied by the system with the temporary folder.
private enum TemporaryLogbook {
    static let shared = Logbook(
        directory: FileManager.default.temporaryDirectory.appending(path: "lone-date-\(UUID().uuidString)"))
}
