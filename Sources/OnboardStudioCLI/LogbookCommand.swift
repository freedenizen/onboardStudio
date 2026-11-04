import ArgumentParser
import Foundation
import MediaKit
import ProjectModel
import TelemetryKit

/// `onboard logbook`: the track days the app keeps (#345, #346).
struct LogbookCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logbook", abstract: "Add track days to the logbook and list what it holds.",
        subcommands: [Add.self, List.self, Export.self, Import.self])

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enter files and folders of telemetry in the logbook.")

        @Argument(help: "Telemetry files, camera clips with GPS, or folders of them.")
        var paths: [String]

        @Option(name: .long, help: "The car for every session added (else the last one at the same circuit).")
        var car: String?

        @Option(name: .long, help: "The driver for every session added (else what the file says).")
        var driver: String?

        @Option(name: .long, help: "The logbook folder (default: the app's).")
        var logbook: String?

        func run() async throws {
            let book = Logbook(directory: logbook.map { URL(fileURLWithPath: $0, isDirectory: true) })
            let urls = paths.map { URL(fileURLWithPath: $0) }
            let reports = await TrackDayImport.run(urls, into: book, tracks: TrackLibrary(), car: car, driver: driver)
            for report in reports { print(report.line) }
            let added = reports.filter(\.isAdded).count
            print("\(added) of \(reports.count) added; the logbook now holds \(book.entries().count) sessions.")
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
            for entry in entries { print(TrackDayImport.Report.describe(entry) + "  (\(entry.file.path))") }
            if entries.isEmpty { print("The logbook is empty. Add a track day with: onboard logbook add <files>") }
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
                let text = laps ? LogbookTransfer.lapsCSV(entries) : LogbookTransfer.sessionsCSV(entries)
                try text.write(to: url, atomically: true, encoding: .utf8)
                print("Wrote \(laps ? "the laps" : "\(entries.count) sessions") to \(url.path)")
            case "md", "markdown":
                try LogbookTransfer.markdown(entries).write(to: url, atomically: true, encoding: .utf8)
                print("Wrote \(entries.count) sessions to \(url.path)")
            default:
                let summary = try LogbookTransfer.export(entries, cars: book.cars(), to: url, includingFiles: withFiles)
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
