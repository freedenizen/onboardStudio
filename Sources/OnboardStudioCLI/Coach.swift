import ArgumentParser
import Foundation
import Importers
import MediaKit
import ProjectModel
import TelemetryKit

struct Coach: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Where a lap lost time against a reference, corner by corner, and what to try next.",
        discussion: """
            Reads one lap of a telemetry file or a project's data input against the session's best lap, \
            the fastest rolling lap, the optimal lap spliced from the best sectors, or another lap; ranks \
            the corners by time lost, says which phase it went in and what to try. See docs/coaching.md.
            """)

    @Argument(help: "A telemetry file, or an .onboardproj package (its first data input unless --input names one).")
    var path: String

    @Option(
        name: .long,
        help: """
            The lap to read. Defaults to the quickest lap other than the reference, or the best lap when the \
            reference is not a lap.
            """)
    var lap: Int?

    @Option(name: .long, help: "What to compare it with: best, rolling, optimal, or lap:N.")
    var reference: String = "best"

    @Option(name: .long, help: "The data input to read, by name, when the project has several.")
    var input: String?

    @Option(name: .long, help: "Units for the notes: metric (km/h, m) or imperial (mph, ft).")
    var units: String = "metric"

    @Flag(name: .long, help: "List every corner that lost time, not only the top three.")
    var all = false

    @Flag(name: .long, help: "Print the analysis as JSON instead of text.")
    var json = false

    @Option(name: .long, help: "Force a specific importer id for a file instead of auto-detecting.")
    var format: String?

    @Option(name: .long, help: "Detect laps in a file from a finish line: lat,lon[,heading[,halfWidthMeters]].")
    var lapLine: String?

    @Option(name: .long, help: "Warm-up crossings to ignore before lap 1 (with --lap-line).")
    var ignoreFirst: Int = 0

    @Option(name: .long, help: "Sectors per lap, for the optimal lap of a file.")
    var sectors: Int = SectorMode.defaultCount

    @Flag(name: .long, help: "Put a file's sector boundaries on the straights between corners, not at equal distances.")
    var cornerAware = false

    func run() async throws {
        let session = try await loadSession()
        let complete = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.end != nil }
        guard !complete.isEmpty else {
            throw ValidationError("No complete laps. Set a start/finish line (--lap-line) or check the file.")
        }
        let reference = try parseReference()
        let chosen: Lap
        if let lap {
            guard let found = complete.first(where: { $0.number == lap }) else {
                throw ValidationError("Lap \(lap) is not a complete lap. Complete laps: \(complete.map(\.number)).")
            }
            chosen = found
        } else {
            chosen = try defaultLap(among: complete, reference: reference)
        }
        let units: CoachingUnits
        switch self.units.lowercased() {
        case "metric": units = .metric
        case "imperial": units = .imperial
        default: throw ValidationError("--units must be metric or imperial.")
        }
        guard let analysis = CoachingAnalysis.analyse(lap: chosen, reference: reference, in: session, units: units)
        else {
            throw ValidationError(
                "Lap \(chosen.number) cannot be read against \(reference.displayName.lowercased()): "
                    + "the file needs a distance channel, position and, for the optimal lap, every sector timed.")
        }
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(CoachingReport(analysis))
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else {
            printReport(analysis, lapNumber: chosen.number, units: units)
        }
    }

    // MARK: - Input

    private func loadSession() async throws -> TelemetrySession {
        let url = URL(fileURLWithPath: path)
        if url.pathExtension == "onboardproj" || url.lastPathComponent == "project.json" {
            let loaded = try await ProjectCompiler.load(url)
            let inputs = loaded.project.dataInputs
            guard !inputs.isEmpty else { throw ValidationError("The project has no data input.") }
            let picked: Input
            if let input {
                guard let found = inputs.first(where: { $0.label == input }) else {
                    throw ValidationError("No data input named '\(input)'. Inputs: \(inputs.map(\.label)).")
                }
                picked = found
            } else {
                picked = inputs[0]
            }
            guard let session = loaded.sessions[picked.id] else {
                throw ValidationError("The data input '\(picked.label)' did not load.")
            }
            return session
        }
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
        var options = SessionBuilder.Options()
        if let lapLine {
            let parts = lapLine.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count >= 2 else { throw ValidationError("--lap-line expects lat,lon[,heading[,halfWidth]].") }
            options.finishLine = FinishLine(
                latitude: parts[0], longitude: parts[1], headingDegrees: parts.count > 2 ? parts[2] : nil,
                halfWidthMeters: parts.count > 3 ? parts[3] : 25)
            options.ignoreFirstCrossings = ignoreFirst
        }
        options.sectorMode = cornerAware ? .cornerAware(count: sectors) : .equalDistance(count: sectors)
        var session = try chosen.importer.importSession(at: url, options: options)
        if session.info.sourceFileName == nil { session.info.sourceFileName = url.lastPathComponent }
        return session
    }

    /// Without `--lap`: the quickest lap that is not the reference itself, so the comparison has
    /// something to say, or the best lap when the reference is spliced or rolling.
    private func defaultLap(among complete: [Lap], reference: CoachingReference) throws -> Lap {
        let byTime = complete.sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
        let excluded: Int?
        switch reference {
        case .sessionBest: excluded = byTime.first?.number
        case .lap(let number): excluded = number
        case .fastestRolling, .compositeOptimal: excluded = nil
        }
        guard let lap = byTime.first(where: { $0.number != excluded }) else {
            throw ValidationError("Only one complete lap: name a different reference, such as --reference rolling.")
        }
        return lap
    }

    private func parseReference() throws -> CoachingReference {
        let text = reference.lowercased()
        switch text {
        case "best": return .sessionBest
        case "rolling": return .fastestRolling
        case "optimal": return .compositeOptimal
        default:
            if text.hasPrefix("lap:"), let number = Int(text.dropFirst(4)) { return .lap(number) }
            throw ValidationError("--reference must be best, rolling, optimal, or lap:N.")
        }
    }

    // MARK: - Text report

    private func printReport(_ analysis: CoachingAnalysis, lapNumber: Int, units: CoachingUnits) {
        let format = CoachingNotes.Formatter(units: units)
        let behind = analysis.totalLoss >= 0 ? "behind" : "ahead"
        print(
            "Lap \(lapNumber) (\(TimeParsing.lapTimeString(analysis.lap.duration, decimals: 2))) against "
                + "\(analysis.referencePhrase) (\(analysis.reference.label), "
                + "\(TimeParsing.lapTimeString(analysis.reference.duration, decimals: 2))): "
                + "\(format.seconds(abs(analysis.totalLoss))) \(behind)")
        if analysis.reference.isSpliced {
            let laps = analysis.reference.pieces.map { String($0.lapNumber) }.joined(separator: ", ")
            print("Spliced from laps \(laps).")
        }
        let confidence = String(format: "%.2f", analysis.delta.confidence)
        print("Aligned by \(alignmentName(analysis.delta.alignment)), confidence \(confidence)")

        let shown = all ? analysis.opportunities : analysis.top
        print("\nOpportunities" + (shown.isEmpty ? ": none — nothing lost against \(analysis.referencePhrase)." : ""))
        for opportunity in shown {
            print(" \(opportunity.rank). \(opportunity.note.headline)")
            for line in opportunity.note.evidence { print("    • \(line)") }
            print("    → \(opportunity.note.suggestion)")
        }

        print("\nCorners")
        let header = [
            pad("Turn", 6), pad("Lost", 8, left: true), pad("Phase", 9), pad("Brake", 12), pad("Min speed", 12),
            pad("Where", 9), pad("Exit", 10), pad("Throttle", 11), "Consistent",
        ]
        print("  " + header.joined(separator: " "))
        for corner in analysis.corners {
            print("  " + row(for: corner, analysis: analysis, format: format).joined(separator: " "))
        }

        if !analysis.warnings.isEmpty {
            print("\nNotes")
            for warning in analysis.warnings { print("  • \(describe(warning))") }
        }
    }

    private func row(
        for corner: CornerComparison, analysis: CoachingAnalysis, format: CoachingNotes.Formatter
    ) -> [String] {
        let lap = corner.lap
        let reference = corner.reference
        func metres(_ difference: Double?, early: String, late: String) -> String {
            guard let difference, abs(difference) >= 1 else { return difference == nil ? "–" : "same" }
            return "\(format.metres(abs(difference))) \(difference > 0 ? early : late)"
        }
        func speed(_ difference: Double) -> String {
            let text = format.speed(abs(difference))
            return text.hasPrefix("0 ") ? "same" : (difference >= 0 ? "+" : "−") + text
        }
        let brake: Double? = {
            guard let own = lap.brakePointMeters, let theirs = reference.brakePointMeters else { return nil }
            return own - theirs
        }()
        let throttle: Double? = {
            guard let own = lap.throttlePickupMeters, let theirs = reference.throttlePickupMeters else { return nil }
            return own - theirs
        }()
        let consistent: String = {
            guard let spread = analysis.consistency?.spread(ofCorner: corner.index) else { return "–" }
            guard let brakeSpread = spread.brakePointSpread else { return spread.isConsistent ? "yes" : "no" }
            return (spread.isConsistent ? "yes" : "no") + " (\(format.metres(brakeSpread)))"
        }()
        return [
            pad(corner.label, 6),
            pad((corner.timeLost >= 0 ? "+" : "−") + format.seconds(abs(corner.timeLost)), 8, left: true),
            pad(corner.worstPhase?.displayName.lowercased() ?? "–", 9),
            pad(metres(brake, early: "early", late: "late"), 12),
            pad(speed(lap.minimumSpeed - reference.minimumSpeed), 12),
            pad(metres(lap.minimumSpeedMeters - reference.minimumSpeedMeters, early: "late", late: "early"), 9),
            pad(speed(lap.exitSpeed - reference.exitSpeed), 10),
            pad(metres(throttle, early: "late", late: "early"), 11),
            consistent,
        ]
    }

    private func alignmentName(_ alignment: LapAlignment) -> String {
        switch alignment {
        case .distance: "distance"
        case .fractionOfLap: "fraction of lap (approximate)"
        case .position: "position"
        }
    }

    private func describe(_ warning: CoachingWarning) -> String {
        switch warning {
        case .approximateAlignment:
            "The two laps could not be lined up by place and were lined up by fraction of lap; "
                + "treat distances as approximate."
        case .pedalsFromSpeedTrace:
            "No brake or throttle channel: brake and throttle points were read from the speed trace."
        case .seamInCorner(let labels):
            "The reference changes lap inside turn \(labels.joined(separator: ", ")), so its speed can step there."
        case .tooFewLapsForConsistency:
            "Fewer than three complete laps: nothing to say about consistency."
        }
    }

    private func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
        let missing = max(0, width - text.count)
        let fill = String(repeating: " ", count: missing)
        return left ? fill + text : text + fill
    }
}
