import ArgumentParser
import Foundation
import Importers
import TelemetryKit

struct Probe: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect a telemetry file: detected format, metadata, channels and laps.")

    @Argument(help: "Path to a telemetry file (RaceRender CSV, RaceChrono CSV, GPX).")
    var path: String

    @Option(name: .long, help: "Force a specific importer id (e.g. racerender-csv) instead of auto-detecting.")
    var format: String?

    @Flag(name: .long, help: "Print the session as JSON instead of a table.")
    var json = false

    @Option(name: .long, help: "Print interpolated values at this time (seconds, session time).")
    var at: Double?

    @Option(name: .long, help: "Detect laps from a finish line: lat,lon[,heading[,halfWidthMeters]].")
    var lapLine: String?

    @Option(name: .long, help: "Warm-up crossings to ignore before lap 1 (with --lap-line).")
    var ignoreFirst: Int = 0

    @Option(name: .long, help: "Sectors per lap for the sector table.")
    var sectors: Int = SectorMode.defaultCount

    @Flag(name: .long, help: "Put sector boundaries on the straights between corners, not at equal distances.")
    var cornerAware = false

    @Flag(name: .long, help: "List the corners found on the reference lap.")
    var corners = false

    @Option(name: .long, help: "Moving-average smoothing window in seconds.")
    var smooth: Double = 0

    @Option(name: .long, help: "Resample linear channels to this rate (Hz).")
    var resample: Double?

    @Option(name: .long, parsing: .upToNextOption, help: "Calculated field as name=expression, e.g. kph=speed*3.6.")
    var calc: [String] = []

    func run() throws {
        let url = URL(fileURLWithPath: path)
        let candidates = try FormatDetector.candidates(for: url)
        let chosen: FormatDetector.Candidate
        if let format {
            guard let match = candidates.first(where: { $0.id == format }) else {
                throw ValidationError("Importer '\(format)' cannot read this file. Candidates: \(candidates.map(\.id))")
            }
            chosen = match
        } else {
            guard let best = candidates.first else { throw ValidationError("Unrecognised file format.") }
            chosen = best
        }
        var session = try chosen.importer.importSession(at: url, options: try buildOptions())
        if session.info.sourceFileName == nil { session.info.sourceFileName = url.lastPathComponent }

        if json {
            try printJSON(session, importerID: chosen.id, confidence: chosen.confidence)
        } else {
            printReport(session, candidates: candidates, chosen: chosen)
        }
    }

    private func buildOptions() throws -> SessionBuilder.Options {
        var options = SessionBuilder.Options()
        options.smoothingSeconds = smooth
        options.resampleHertz = resample
        options.calculatedFields = try calc.map { entry in
            let parts = entry.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count == 2 else { throw ValidationError("--calc expects name=expression, got '\(entry)'.") }
            _ = try Expression(parts[1])
            return CalculatedField(name: parts[0], expression: parts[1])
        }
        if let lapLine {
            let parts = lapLine.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 2 else { throw ValidationError("--lap-line expects lat,lon[,heading[,halfWidth]].") }
            options.finishLine = FinishLine(
                latitude: parts[0], longitude: parts[1], headingDegrees: parts.count > 2 ? parts[2] : nil,
                halfWidthMeters: parts.count > 3 ? parts[3] : 25)
            options.ignoreFirstCrossings = ignoreFirst
        }
        options.sectorMode = cornerAware ? .cornerAware(count: sectors) : .equalDistance(count: sectors)
        return options
    }

    // MARK: - Text report

    private func printReport(
        _ session: TelemetrySession, candidates: [FormatDetector.Candidate], chosen: FormatDetector.Candidate
    ) {
        printHeader(session, candidates: candidates, chosen: chosen)
        print("")
        printChannels(session)
        if !session.laps.isEmpty { printLaps(session) }
        if let analysis = session.sectors, analysis.count > 1 { printSectors(analysis) }
        if corners { printCorners(session) }
        if let at { printValues(session, at: at) }
    }

    private func printHeader(
        _ session: TelemetrySession, candidates: [FormatDetector.Candidate], chosen: FormatDetector.Candidate
    ) {
        print("File:      \(session.info.sourceFileName ?? path)")
        print("Format:    \(chosen.displayName) [\(chosen.id)] (\(chosen.confidence))")
        if candidates.count > 1 {
            let others = candidates.dropFirst().map { "\($0.id) (\($0.confidence))" }
            print("Also:      \(others.joined(separator: ", "))")
        }
        if let title = session.info.title { print("Title:     \(title)") }
        if let track = session.info.trackName { print("Track:     \(track)") }
        if let match = CircuitCatalog.identify(session) {
            let margin = match.runnerUpKm.map { String(format: ", next %.0f km", $0) } ?? ""
            let agrees = match.nameAgrees ? ", name agrees" : ""
            print(
                "Circuit:   \(match.circuit.displayName) [\(match.circuit.id)]"
                    + String(format: "  (%.2f km from the session centre", match.distanceKm) + margin + agrees + ")")
        }
        if let driver = session.info.driverName { print("Driver:    \(driver)") }
        if let created = session.info.createdAt {
            print("Created:   \(created.formatted(date: .abbreviated, time: .shortened))")
        }
        if let range = session.timeRange {
            let duration = TimeParsing.lapTimeString(session.duration)
            print("Time:      \(fmt(range.lowerBound)) … \(fmt(range.upperBound))  (\(duration))")
        }
    }

    private func printChannels(_ session: TelemetrySession) {
        let widths = [28, 24, 7, 8, 12, 12, 7]
        print(row(["Role", "Name", "Unit", "Samples", "Min", "Max", "Hz"], widths: widths))
        for channel in session.orderedChannels {
            let cells = [
                channel.role.identifier,
                String(channel.name.prefix(24)),
                channel.unit.symbol,
                String(channel.count),
                fmt(channel.minValue),
                fmt(channel.maxValue),
                channel.sampleRate.map { String(format: "%.1f", $0) } ?? "-",
            ]
            print(row(cells, widths: widths))
        }
    }

    private func printLaps(_ session: TelemetrySession) {
        print("\nLaps:")
        for lap in session.laps {
            let duration = lap.duration.map(TimeParsing.lapTimeString) ?? "…"
            let flag = lap.isComplete ? "" : "  (partial)"
            let number = pad(String(lap.number), 3)
            let start = pad(fmt(lap.start), 10, left: true)
            print("  Lap \(number)  start \(start)  time \(pad(duration, 10, left: true))\(flag)")
        }
    }

    private func printSectors(_ analysis: SectorAnalysis) {
        let layout = analysis.layout
        let boundaries = layout.boundaryDistances.map { String(format: "%.0f", $0) }.joined(separator: ", ")
        print("\nSectors (\(layout.count), from lap \(layout.referenceLapNumber) at \(boundaries) m):")
        let bests = analysis.best
        let names = (0..<layout.count).map { SectorLayout.name(of: $0) }
        print("  " + pad("Lap", 6) + names.map { pad($0, 10, left: true) }.joined(separator: " "))
        for lap in analysis.laps {
            let cells = lap.times.enumerated().map { index, time -> String in
                guard let time else { return pad("…", 10, left: true) }
                // A star marks the lap that owns the sector's best time.
                let star = bests[index]?.lapNumber == lap.lapNumber ? "*" : " "
                return pad(TimeParsing.lapTimeString(time, decimals: 2) + star, 10, left: true)
            }
            print("  " + pad(String(lap.lapNumber), 6) + cells.joined(separator: " "))
        }
        let bestCells = bests.map { best in
            pad(best.map { TimeParsing.lapTimeString($0.time, decimals: 2) } ?? "…", 10, left: true)
        }
        print("  " + pad("best", 6) + bestCells.joined(separator: " "))
        if let theoretical = analysis.theoreticalLapTime {
            print("  Theoretical best lap: \(TimeParsing.lapTimeString(theoretical, decimals: 2))")
        }
    }

    private func printCorners(_ session: TelemetrySession) {
        guard let reference = Sectors.referenceLap(in: session) else { return }
        let found = CornerDetector.corners(of: reference, in: session)
        print("\nCorners on lap \(reference.number) (\(found.count)):")
        for (index, corner) in found.enumerated() {
            let turn = corner.turnsRight ? "right" : "left"
            print(
                "  \(pad(String(index + 1), 4))"
                    + "  \(pad(String(format: "%.0f", corner.startDistance), 6, left: true))"
                    + " … \(pad(String(format: "%.0f", corner.endDistance), 6, left: true)) m"
                    + "  apex \(pad(String(format: "%.0f", corner.apexDistance), 6, left: true)) m"
                    + "  \(pad(turn, 6)) \(String(format: "%.0f", abs(corner.headingChangeDegrees)))°")
        }
    }

    private func printValues(_ session: TelemetrySession, at time: Double) {
        let sample = TelemetrySampler(session: session).sample(at: time)
        print("\nValues at \(fmt(time)) s:")
        for channel in session.orderedChannels {
            if let value = sample[channel.role] {
                print("  \(pad(channel.role.identifier, 28)) \(pad(fmt(value), 12, left: true)) \(channel.unit.symbol)")
            }
        }
        if let lap = sample.lapTiming.currentLap {
            print("  lap \(lap.number), elapsed \(TimeParsing.lapTimeString(sample.lapTiming.elapsedInLap ?? 0))")
        }
    }

    /// Pads `text` to `width` characters (right-aligned when `left` is true).
    private func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
        let missing = max(0, width - text.count)
        let fill = String(repeating: " ", count: missing)
        return left ? fill + text : text + fill
    }

    private func row(_ cells: [String], widths: [Int]) -> String {
        zip(cells, widths).enumerated().map { index, pair in pad(pair.0, pair.1, left: index >= 3) }.joined(
            separator: " ")
    }

    private func fmt(_ value: Double?) -> String {
        guard let value else { return "-" }
        if abs(value) >= 1_000_000 { return String(format: "%.2f", value) }
        return value == value.rounded() ? String(format: "%.0f", value) : String(format: "%.3f", value)
    }
}

// MARK: - JSON

extension Probe {

    private struct ChannelSummary: Encodable {
        let role: String
        let name: String
        let unit: String
        let samples: Int
        let min: Double?
        let max: Double?
        let sampleRate: Double?
        let interpolation: String
    }

    private struct LapSummary: Encodable {
        let number: Int
        let start: Double
        let end: Double?
        let duration: Double?
        let isComplete: Bool
    }

    private struct CircuitSummary: Encodable {
        let id: String
        let name: String
        let country: String
        let distanceKm: Double
        let runnerUpKm: Double?
        let nameAgrees: Bool
        let isConfident: Bool
    }

    private struct SectorSummary: Encodable {
        let boundaryDistances: [Double]
        let lapLengthMeters: Double
        let referenceLap: Int
        let bestTimes: [Double?]
        let theoreticalLapTime: Double?
        let laps: [LapSectorSummary]
    }

    private struct LapSectorSummary: Encodable {
        let number: Int
        let times: [Double?]
    }

    private struct Report: Encodable {
        let importer: String
        let confidence: Int
        let info: SessionInfo
        let start: Double?
        let end: Double?
        let duration: Double
        let channels: [ChannelSummary]
        let laps: [LapSummary]
        let sectors: SectorSummary?
        let circuit: CircuitSummary?
    }

    private func printJSON(_ session: TelemetrySession, importerID: String, confidence: ImportConfidence) throws {
        let report = Report(
            importer: importerID,
            confidence: confidence.rawValue,
            info: session.info,
            start: session.timeRange?.lowerBound,
            end: session.timeRange?.upperBound,
            duration: session.duration,
            channels: session.orderedChannels.map {
                ChannelSummary(
                    role: $0.role.identifier, name: $0.name, unit: $0.unit.symbol, samples: $0.count, min: $0.minValue,
                    max: $0.maxValue, sampleRate: $0.sampleRate, interpolation: $0.interpolation.rawValue)
            },
            laps: session.laps.map {
                LapSummary(
                    number: $0.number, start: $0.start, end: $0.end, duration: $0.duration, isComplete: $0.isComplete)
            },
            sectors: session.sectors.map { analysis in
                SectorSummary(
                    boundaryDistances: analysis.layout.boundaryDistances,
                    lapLengthMeters: analysis.layout.lapLengthMeters,
                    referenceLap: analysis.layout.referenceLapNumber,
                    bestTimes: analysis.best.map { $0?.time },
                    theoreticalLapTime: analysis.theoreticalLapTime,
                    laps: analysis.laps.map { LapSectorSummary(number: $0.lapNumber, times: $0.times) })
            },
            circuit: CircuitCatalog.identify(session).map {
                CircuitSummary(
                    id: $0.circuit.id, name: $0.circuit.name, country: $0.circuit.country,
                    distanceKm: $0.distanceKm, runnerUpKm: $0.runnerUpKm, nameAgrees: $0.nameAgrees,
                    isConfident: $0.isConfident)
            })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(report)
        print(String(bytes: data, encoding: .utf8) ?? "{}")
    }
}
