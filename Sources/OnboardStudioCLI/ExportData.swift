import ArgumentParser
import Foundation
import Importers
import TelemetryKit

/// `onboard export-data` (#563): a telemetry file, or one lap of it, written as CSV, GPX, KML or VBO.
struct ExportData: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-data",
        abstract: "Write a telemetry file, or one lap of it, as CSV (every channel), GPX, KML or VBO.")

    @Argument(help: "Path to a telemetry file the app reads.")
    var path: String

    @Option(name: .long, help: "csv, gpx, kml or vbo.")
    var format: String = "csv"

    @Option(name: .long, help: "One lap: its number, or \"best\". Without it, the whole session.")
    var lap: String?

    @Option(name: .long, help: "Where to write it. Defaults to the file's name with the format's extension.")
    var out: String?

    func run() throws {
        guard let chosen = TelemetryExport.Format(rawValue: format.lowercased()) else {
            throw ValidationError("--format is csv, gpx, kml or vbo, not \(format).")
        }
        let url = URL(fileURLWithPath: path)
        let session = try FormatDetector.importSession(at: url)
        var scope = TelemetryExport.Scope.session
        if let lap {
            if lap.lowercased() == "best" {
                guard let best = LapDeltas.sessionBest(in: session) else {
                    throw ValidationError("The file has no complete lap to call its best.")
                }
                scope = .lap(best.number)
            } else if let number = Int(lap) {
                scope = .lap(number)
            } else {
                throw ValidationError("--lap is a lap number or \"best\", not \(lap).")
            }
        }
        let name = url.deletingPathExtension().lastPathComponent
        let data = try TelemetryExport.export(session, as: chosen, scope: scope, name: name)
        let suffix: String =
            switch scope {
            case .session: ""
            case .lap(let number): "-lap\(number)"
            }
        let destination =
            out.map { URL(fileURLWithPath: $0) }
            ?? url.deletingLastPathComponent().appending(path: "\(name)\(suffix).\(chosen.fileExtension)")
        try data.write(to: destination)
        print("Wrote \(destination.path)")
    }
}
