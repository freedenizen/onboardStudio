import ArgumentParser
import Foundation
import MediaKit
import ProjectModel
import TelemetryKit

/// `onboard logbook`: the track days the app keeps (#345, #346, #398).
struct LogbookCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logbook", abstract: "Begin track days, add sessions to them, and list what the logbook holds.",
        subcommands: [NewDay.self, Days.self, Add.self, List.self, Export.self, Import.self])

    /// "23 Aug 2026 · Sonoma Raceway — Miata, 3 sessions, 2 clips".
    static func describe(_ day: TrackDay, sessions: Int) -> String {
        var parts: [String] = []
        if !day.car.isEmpty { parts.append(day.car) }
        parts.append("\(sessions) session\(sessions == 1 ? "" : "s")")
        if !day.clips.isEmpty { parts.append("\(day.clips.count) clip\(day.clips.count == 1 ? "" : "s")") }
        return "\(day.label) — \(parts.joined(separator: ", "))"
    }

    /// A day named on the command line: its id, or its date (`2026-08-23`) when one day was
    /// driven then — with several, the circuit narrows it.
    static func day(named text: String, circuit: String?, in logbook: Logbook) throws -> TrackDay {
        let days = logbook.days()
        if let id = UUID(uuidString: text), let found = days.first(where: { $0.id == id }) { return found }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = .current  // a day is a day where the driver is, not at Greenwich
        guard let date = formatter.date(from: text) else {
            throw ValidationError("“\(text)” is neither a day's id nor a date like 2026-08-23.")
        }
        let when = TrackDay.startOfDay(date)
        var candidates = days.filter { Calendar(identifier: .gregorian).isDate($0.date, inSameDayAs: when) }
        if let circuit, !circuit.isEmpty {
            candidates = candidates.filter {
                $0.title.localizedCaseInsensitiveContains(circuit) || $0.circuitID == circuit
            }
        }
        guard let only = candidates.first, candidates.count == 1 else {
            if candidates.isEmpty {
                throw ValidationError("No track day on \(text). Begin one with: onboard logbook new-day")
            }
            let names = candidates.map { "\($0.label) (\($0.id.uuidString))" }.joined(separator: "; ")
            throw ValidationError("More than one day on \(text): \(names). Name it by id, or add --circuit.")
        }
        return only
    }

    struct NewDay: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "new-day", abstract: "Begin a track day: the date, the circuit, the car — before any file.")

        @Option(name: .long, help: "The day, as 2026-08-23 (default: today).")
        var date: String?

        @Option(name: .long, help: "The circuit: a name to search the catalogue for, or a catalogue id (Q112563).")
        var circuit: String?

        @Option(name: .long, help: "The car driven.")
        var car: String?

        @Option(name: .long, help: "The driver.")
        var driver: String?

        @Option(name: .long, help: "Notes for the day.")
        var notes: String?

        @Option(name: .long, help: "The logbook folder (default: the app's).")
        var logbook: String?

        func run() async throws {
            let book = Logbook(directory: logbook.map { URL(fileURLWithPath: $0, isDirectory: true) })
            var when = Date()
            if let date {
                let formatter = ISO8601DateFormatter()
                formatter.formatOptions = [.withFullDate]
                formatter.timeZone = .current  // a day is a day where the driver is, not at Greenwich
                guard let parsed = formatter.date(from: date) else { throw ValidationError("--date wants 2026-08-23.") }
                when = parsed
            }
            var circuitID: String?
            var trackName: String?
            if let circuit, !circuit.isEmpty {
                if CircuitCatalog.circuit(id: circuit) != nil {
                    circuitID = circuit
                } else if let match = CircuitCatalog.search(circuit, limit: 1).first {
                    circuitID = match.id
                } else {
                    trackName = circuit
                }
            }
            let day = TrackDay(
                date: when, circuitID: circuitID, trackName: trackName, car: car ?? "", driver: driver ?? "",
                notes: notes ?? "")
            try book.saveDay(day)
            print(
                "Began \(day.label) (\(day.id.uuidString)). "
                    + "Add its files with: onboard logbook add <files> --day \(day.id.uuidString)"
            )
        }
    }

    struct Days: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Every track day in the logbook, newest first.")

        @Option(name: .long, help: "The logbook folder (default: the app's).")
        var logbook: String?

        @Flag(name: .long, help: "Print the days as JSON.")
        var json = false

        func run() async throws {
            let book = Logbook(directory: logbook.map { URL(fileURLWithPath: $0, isDirectory: true) })
            try book.ensureDays()
            let days = book.days()
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                print(String(data: try encoder.encode(days), encoding: .utf8) ?? "[]")
                return
            }
            let entries = book.entries()
            for day in days {
                let count = entries.filter { $0.trackDayID == day.id }.count
                print("\(LogbookCommand.describe(day, sessions: count))  (\(day.id.uuidString))")
            }
            if days.isEmpty { print("The logbook has no track days. Begin one with: onboard logbook new-day") }
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enter files and folders of telemetry in the logbook.")

        @Argument(help: "Telemetry files, camera clips with GPS, or folders of them.")
        var paths: [String]

        @Option(name: .long, help: "The car for every session added (else the last one at the same circuit).")
        var car: String?

        @Option(name: .long, help: "The driver for every session added (else what the file says).")
        var driver: String?

        @Option(
            name: .long,
            help: "The track day every file goes on, whatever its own date: its id, or its date (2026-08-23).")
        var day: String?

        @Option(name: .long, help: "With --day as a date: the circuit, when more than one day was driven then.")
        var circuit: String?

        @Option(name: .long, help: "The logbook folder (default: the app's).")
        var logbook: String?

        func run() async throws {
            let book = Logbook(directory: logbook.map { URL(fileURLWithPath: $0, isDirectory: true) })
            let chosen = try day.map { try LogbookCommand.day(named: $0, circuit: circuit, in: book) }
            let urls = paths.map { URL(fileURLWithPath: $0) }
            let reports = await TrackDayImport.run(
                urls, into: book, tracks: TrackLibrary(), car: car, driver: driver, day: chosen)
            for report in reports { print(report.line) }
            let added = reports.filter(\.isAdded).count
            let clips = reports.filter(\.isClip).count
            let onto = chosen.map { " on \($0.label)" } ?? ""
            print(
                "\(added) of \(reports.count) added\(clips > 0 ? ", \(clips) clips" : "")\(onto); "
                    + "the logbook now holds \(book.entries().count) sessions.")
        }
    }

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(abstract: "Every session in the logbook, newest first.")

        @Option(name: .long, help: "The logbook folder (default: the app's).")
        var logbook: String?

        @Flag(name: .long, help: "Print the entries as JSON.")
        var json = false

        func run() async throws {
            let book = Logbook(directory: logbook.map { URL(fileURLWithPath: $0, isDirectory: true) })
            let entries = book.entries()
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                print(String(data: try encoder.encode(entries), encoding: .utf8) ?? "[]")
                return
            }
            let days = Dictionary(book.days().map { ($0.id, $0.label) }, uniquingKeysWith: { first, _ in first })
            for entry in entries {
                let day = entry.trackDayID.flatMap { days[$0] }.map { "[\($0)] " } ?? ""
                print(day + TrackDayImport.Report.describe(entry) + "  (\(entry.file.path))")
            }
            if entries.isEmpty { print("The logbook is empty. Begin a day with: onboard logbook new-day") }
        }
    }

    struct Export: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Write the logbook as a folder of entries, or as CSV or Markdown.")

        @Argument(help: "The folder to write entries into, or the .csv / .md file to write.")
        var destination: String

        @Flag(name: .long, help: "Copy each session's data file into the folder too.")
        var withFiles = false

        @Flag(name: .long, help: "With a .csv destination: one line per lap instead of per session.")
        var laps = false

        @Option(name: .long, help: "The logbook folder (default: the app's).")
        var logbook: String?

        func run() async throws {
            let book = Logbook(directory: logbook.map { URL(fileURLWithPath: $0, isDirectory: true) })
            let url = URL(fileURLWithPath: destination)
            let entries = book.entries()
            switch url.pathExtension.lowercased() {
            case "csv":
                let text =
                    laps ? LogbookTransfer.lapsCSV(entries) : LogbookTransfer.sessionsCSV(entries, days: book.days())
                try text.write(to: url, atomically: true, encoding: .utf8)
                print("Wrote \(laps ? "the laps" : "\(entries.count) sessions") to \(url.path)")
            case "md", "markdown":
                try LogbookTransfer.markdown(entries).write(to: url, atomically: true, encoding: .utf8)
                print("Wrote \(entries.count) sessions to \(url.path)")
            default:
                let summary = try LogbookTransfer.export(
                    entries, days: book.days(), cars: book.cars(), to: url, includingFiles: withFiles)
                let files = withFiles ? ", \(summary.filesCopied) data files copied" : ""
                print("Wrote \(summary.written) sessions to \(url.path)\(files)")
            }
        }
    }

    struct Import: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Read a folder of entries into the logbook, merging by each file's bytes.")

        @Argument(help: "A folder written by export, or any folder of .onboardsession files.")
        var folder: String

        @Option(name: .long, help: "The logbook folder (default: the app's).")
        var logbook: String?

        func run() async throws {
            let book = Logbook(directory: logbook.map { URL(fileURLWithPath: $0, isDirectory: true) })
            let summary = try LogbookTransfer.import(from: URL(fileURLWithPath: folder, isDirectory: true), into: book)
            print(
                "\(summary.added) added, \(summary.updated) updated, \(summary.skipped) already there; "
                    + "the logbook now holds \(book.entries().count) sessions.")
        }
    }
}
