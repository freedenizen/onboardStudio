import ArgumentParser
import Foundation
import MediaKit
import ProjectModel
import TelemetryKit

/// `onboard logbook`: the track days the app keeps (#345, #346).
struct LogbookCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "logbook", abstract: "Add track days to the logbook and list what it holds.",
        subcommands: [Add.self, List.self])

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
}
