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

    @Option(
        name: .long,
        help: "How the two laps are lined up: distance (metre for metre, the default within a session) or position.")
    var align: String?

    @Option(name: .long, help: "Units for the notes: metric (km/h, m) or imperial (mph, ft).")
    var units: String = "metric"

    @Flag(name: .long, help: "List every corner that lost time, not only the top three.")
    var all = false

    @Flag(name: .long, help: "Print the debrief sheet as Markdown: the notes, the opportunities and the corner table.")
    var markdown = false

    @Flag(name: .long, help: "Print the analysis as JSON instead of text.")
    var json = false

    @Option(
        name: .long,
        help: """
            Stretches held up by traffic or a flag, in seconds of the data file: start-end[:flag], comma-separated \
            (312.5-330,1204-1215:flag). Corners they cover are not coached. A project's own marks apply without it.
            """)
    var traffic: String?

    @Flag(
        name: .long,
        help: """
            List every stretch of the session the telemetry suggests was traffic: a lift where the other laps \
            are flat out, or a corner far slower than usual. Suggestions only; they change nothing.
            """)
    var suggestTraffic = false

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
        let session = try await markedSession()
        let complete = LapDeltas.demotingShortLaps(session.laps, distance: session[.distance])
            .filter { $0.isComplete && $0.end != nil }
        guard !complete.isEmpty else {
            throw ValidationError("No complete laps. Set a start/finish line (--lap-line) or check the file.")
        }
        let logbookReference = try parseLogbookReference(session: session)
        let reference = logbookReference == nil ? try parseReference() : .sessionBest
        let chosen: Lap
        if let lap {
            guard let found = complete.first(where: { $0.number == lap }) else {
                throw ValidationError("Lap \(lap) is not a complete lap. Complete laps: \(complete.map(\.number)).")
            }
            chosen = found
        } else {
            chosen = try defaultLap(among: complete, reference: reference, in: session)
        }
        let units: CoachingUnits
        switch self.units.lowercased() {
        case "metric": units = .metric
        case "imperial": units = .imperial
        default: throw ValidationError("--units must be metric or imperial.")
        }
        let options = try coachingOptions()
        let analysis: CoachingAnalysis?
        if let logbookReference {
            analysis = LapProfile(lap: chosen, in: session).flatMap { lapProfile in
                CoachingAnalysis.analyse(
                    lap: lapProfile, in: session, reference: logbookReference.profile,
                    referencePhrase: logbookReference.phrase, sameSession: false, units: units, options: options)
            }
        } else {
            analysis = CoachingAnalysis.analyse(
                lap: chosen, reference: reference, in: session, units: units, options: options)
        }
        guard let analysis else {
            throw ValidationError(
                "Lap \(chosen.number) cannot be read against \(reference.displayName.lowercased()): "
                    + "the file needs a distance channel, position and, for the optimal lap, every sector timed.")
        }
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(CoachingReport(analysis))
            print(String(data: data, encoding: .utf8) ?? "{}")
        } else if markdown {
            let sheet = CoachingSheet(
                analysis: analysis, lapNumber: chosen.number, units: units, title: session.info.trackName ?? "",
                subtitle: session.info.createdAt.map(ProjectDetails.iso) ?? "",
                warnings: analysis.warnings.map(describe))
            print(sheet.markdown)
        } else {
            printReport(analysis, lapNumber: chosen.number, units: units)
            if suggestTraffic { printSuggestions(analysis, session: session, units: units) }
        }
    }

    // MARK: - Input

    fileprivate func loadSession() async throws -> TelemetrySession {
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
    /// something to say, or the best lap when the reference is spliced or rolling; one with no
    /// traffic mark when there is one (#571).
    private func defaultLap(among complete: [Lap], reference: CoachingReference, in session: TelemetrySession) throws
        -> Lap
    {
        let byTime = complete.sorted { ($0.duration ?? .infinity) < ($1.duration ?? .infinity) }
        let excluded: Int?
        switch reference {
        case .sessionBest: excluded = byTime.first?.number
        case .lap(let number): excluded = number
        case .fastestRolling, .compositeOptimal: excluded = nil
        }
        guard let lap = complete.quickest(excluding: excluded, in: session) else {
            throw ValidationError("Only one complete lap: name a different reference, such as --reference rolling.")
        }
        return lap
    }

    /// `--reference logbook:pb`, `logbook:last` or `logbook:<yyyy-mm-dd>`: a session from the
    /// logbook at the same circuit as `session` (#352); `nil` for any other reference.
    private func parseLogbookReference(session: TelemetrySession) throws -> (profile: LapProfile, phrase: String)? {
        let text = reference.lowercased()
        guard text.hasPrefix("logbook:") else { return nil }
        let which = String(text.dropFirst("logbook:".count))
        let entries = Logbook().entries()
        let url = URL(fileURLWithPath: path)
        let input = Input(label: "", source: MediaReference(path: path), kind: .data(DataInputSettings()))
        let own = try? LogbookEntry.hash(of: url).hex
        // The circuit the logbook has this very file under, where one named afterwards is kept
        // (#455); else what the file itself says.
        let filed = entries.first { $0.file.contentHash == own }.map(LogbookFilter.circuitKey(of:)) ?? ""
        let key = filed.isEmpty ? LogbookReferences.circuitKey(for: input, session: session, entries: []) : filed
        let candidates = LogbookReferences.sessions(at: key, in: entries, excluding: own)
        let entry: LogbookEntry?
        switch which {
        case "pb": entry = LogbookReferences.personalBest(in: candidates)
        case "last": entry = LogbookReferences.lastVisit(in: candidates)
        default: entry = candidates.first { $0.date.map(ProjectDetails.iso) == which }
        }
        guard let entry else {
            throw ValidationError(
                "No logbook session matches '\(which)' at this circuit (\(candidates.count) others there). "
                    + "Use logbook:pb, logbook:last or logbook:<yyyy-mm-dd>.")
        }
        guard let other = LogbookReferences.load(entry),
            let profile = LogbookReferences.profile(of: entry, lap: nil, session: other)
        else { throw ValidationError("The logbook session's file could not be read: \(entry.file.path)") }
        return (profile, LogbookReferences.phrase(for: entry, lap: nil))
    }

    private func parseReference() throws -> CoachingReference {
        let text = reference.lowercased()
        switch text {
        case "best": return .sessionBest
        case "rolling": return .fastestRolling
        case "optimal": return .compositeOptimal
        default:
            if text.hasPrefix("lap:"), let number = Int(text.dropFirst(4)) { return .lap(number) }
            throw ValidationError("--reference must be best, rolling, optimal, lap:N, or logbook:pb|last|<date>.")
        }
    }

    // MARK: - Text report

    private func printReport(_ analysis: CoachingAnalysis, lapNumber: Int, units: CoachingUnits) {
        print(analysis.headline(lapNumber: lapNumber, units: units))
        if let spliced = analysis.splicedFrom { print(spliced + ".") }
        print(analysis.alignmentLine)

        let shown = all ? analysis.opportunities : analysis.top
        print("\nOpportunities" + (shown.isEmpty ? ": none — nothing lost against \(analysis.referencePhrase)." : ""))
        for opportunity in shown {
            print(" \(opportunity.rank). \(opportunity.note.headline)")
            for line in opportunity.note.evidence { print("    • \(line)") }
            print("    → \(opportunity.note.suggestion)")
        }

        print("\nCorners")
        let widths = [6, 8, 9, 12, 12, 9, 10, 11]
        let header = ["Turn", "Lost", "Phase", "Brake", "Min speed", "Where", "Exit", "Throttle"]
        print("  " + zip(header, widths).map { pad($0, $1, left: $0 == "Lost") }.joined(separator: " ") + " Consistent")
        let format = CoachingNotes.Formatter(units: units)
        for row in analysis.rows(units: units) {
            let lost = (row.timeLost >= 0 ? "+" : "−") + format.seconds(abs(row.timeLost))
            let cells = [
                row.label, lost, row.phase, row.brake, row.minimumSpeed, row.minimumPoint, row.exitSpeed, row.throttle,
            ]
            let line = zip(cells, widths).map { pad($0, $1, left: $0 == lost) }.joined(separator: " ")
            print("  " + line + " " + row.consistent)
        }

        if !analysis.warnings.isEmpty {
            print("\nNotes")
            for warning in analysis.warnings { print("  • \(describe(warning))") }
        }
    }

    private func pad(_ text: String, _ width: Int, left: Bool = false) -> String {
        let missing = max(0, width - text.count)
        let fill = String(repeating: " ", count: missing)
        return left ? fill + text : text + fill
    }
}

extension Coach {
    /// The session with `--traffic`'s marks, when given, in place of any the project had.
    func markedSession() async throws -> TelemetrySession {
        var session = try await loadSession()
        if let traffic { session.traffic = try Self.parseTraffic(traffic) }
        return session
    }

    /// `start-end[:flag]`, comma-separated, as `--traffic` takes it.
    static func parseTraffic(_ text: String) throws -> [TrafficSpan] {
        try text.split(separator: ",").map { item in
            let parts = item.trimmingCharacters(in: .whitespaces).split(separator: ":")
            let bounds = parts.first.map { $0.split(separator: "-").compactMap { Double($0) } } ?? []
            let kind = parts.count > 1 ? TrafficSpan.Kind(rawValue: String(parts[1]).lowercased()) : .traffic
            guard bounds.count == 2, parts.count <= 2, let kind else {
                throw ValidationError("--traffic expects start-end[:flag] in seconds, comma-separated; got '\(item)'.")
            }
            return TrafficSpan(start: bounds[0], end: bounds[1], kind: kind)
        }
    }

    func describe(_ warning: CoachingWarning) -> String {
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
        case .traffic(let labels):
            "Marked as traffic or a flag, so not coached: turn \(labels.joined(separator: ", "))."
        }
    }
}

extension Coach {
    /// The session's traffic suggestions (#572), each with its lap, its stretch of the data file's
    /// time and what the telemetry saw, to check against the video.
    func printSuggestions(_ analysis: CoachingAnalysis, session: TelemetrySession, units: CoachingUnits) {
        let suggestions = analysis.suggestions
        print("\nTraffic suggestions" + (suggestions.isEmpty ? ": none." : ""))
        let origin = session.laps.first?.start ?? 0
        for suggestion in suggestions {
            // The file's own seconds, as --traffic takes them, and how far into the laps that is.
            let window = String(format: "%.1f–%.1f s", suggestion.window.start, suggestion.window.end)
            let seconds = Int(max(0, suggestion.window.start - origin))
            let into = String(format: "%d:%02d", seconds / 60, seconds % 60)
            print(
                "  Lap \(suggestion.lapNumber), Turn \(suggestion.label) (\(window), \(into) in): "
                    + suggestion.sentence(units: units) + ".")
        }
    }

    /// What `--align` and `--suggest-traffic` ask of the reading.
    func coachingOptions() throws -> CoachingOptions {
        var options = CoachingOptions()
        options.suggestsTraffic = suggestTraffic
        switch align?.lowercased() {
        case nil: break
        case "distance": options.alignment = .distance
        case "position": options.alignment = .byPosition
        default: throw ValidationError("--align must be distance or position.")
        }
        return options
    }
}
