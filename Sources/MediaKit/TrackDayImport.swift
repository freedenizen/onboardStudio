import Foundation
import Importers
import ProjectModel
import TelemetryKit

/// A track day into the logbook (#346): every recognised telemetry file and every camera clip with
/// embedded GPS among the files and folders given becomes an entry; a file already there (same
/// bytes) is skipped; each file gets a line in the user's words.
public enum TrackDayImport {
    public enum Outcome: Sendable, Equatable {
        case added(LogbookEntry)
        case alreadyThere(LogbookEntry)
        case notRecognised
        case noData
        case failed(String)
    }

    public struct Report: Sendable {
        public let url: URL
        public let outcome: Outcome

        public var isAdded: Bool { if case .added = outcome { return true } else { return false } }

        /// "session_3.csv — added: Sonoma, 12 laps, best 1:56.88".
        public var line: String {
            let name = url.lastPathComponent
            switch outcome {
            case .added(let entry): return "\(name) — added: \(Self.describe(entry))"
            case .alreadyThere(let entry): return "\(name) — already in the logbook as \(Self.describe(entry))"
            case .notRecognised: return "\(name) — not a telemetry file this app reads"
            case .noData: return "\(name) — no position or laps in it"
            case .failed(let reason): return "\(name) — could not be read: \(reason)"
            }
        }

        public static func describe(_ entry: LogbookEntry) -> String {
            var parts = [entry.title]
            if let date = entry.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
            parts.append(entry.laps.isEmpty ? "no laps" : "\(entry.completeLapCount) laps")
            if let best = entry.bestLap { parts.append("best \(TimeParsing.lapTimeString(best))") }
            return parts.joined(separator: ", ")
        }
    }

    /// What a folder is searched for: every importer's extensions, and camera clips.
    public static let fileExtensions: Set<String> = {
        var extensions = Set(FormatDetector.importers.flatMap { type(of: $0).fileExtensions.map { $0.lowercased() } })
        extensions.formUnion(["mp4", "mov", "360"])
        return extensions
    }()

    /// Folders opened recursively (packages and hidden files left alone), files kept when their
    /// extension is one the app reads, in name order.
    public static func files(in urls: [URL]) -> [URL] {
        var found: [URL] = []
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }
            if isDirectory.boolValue, url.pathExtension.isEmpty {
                let enumerator = FileManager.default.enumerator(
                    at: url, includingPropertiesForKeys: [.isRegularFileKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
                while let child = enumerator?.nextObject() as? URL {
                    let isPackage = (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
                    if !child.pathExtension.isEmpty, isPackage {
                        enumerator?.skipDescendants()
                        continue
                    }
                    if fileExtensions.contains(child.pathExtension.lowercased()) { found.append(child) }
                }
            } else if !isDirectory.boolValue, fileExtensions.contains(url.pathExtension.lowercased()) {
                found.append(url)
            }
        }
        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Imports every file into `logbook`. `car` for the whole batch, else the last session at the
    /// same circuit's car; `driver` likewise, else what the file says. `progress` is told the
    /// index, the count and the file before each one.
    public static func run(
        _ urls: [URL], into logbook: Logbook, tracks: TrackLibrary? = nil, car: String? = nil, driver: String? = nil,
        progress: @Sendable (Int, Int, URL) -> Void = { _, _, _ in }
    ) async -> [Report] {
        let files = files(in: urls)
        var reports: [Report] = []
        for (index, url) in files.enumerated() {
            progress(index, files.count, url)
            let outcome = importOne(url, into: logbook, tracks: tracks, car: car, driver: driver)
            reports.append(Report(url: url, outcome: outcome))
            await Task.yield()
        }
        return reports
    }

    static func importOne(_ url: URL, into logbook: Logbook, tracks: TrackLibrary?, car: String?, driver: String?)
        -> Outcome
    {
        do {
            let (hash, _) = try LogbookEntry.hash(of: url)
            if let existing = logbook.entry(forContentHash: hash) { return .alreadyThere(existing) }
            guard let candidate = try FormatDetector.detect(url) else { return .notRecognised }
            var session = try candidate.importer.importSession(at: url, options: SessionBuilder.Options())
            guard session[.latitude] != nil || !session.laps.isEmpty || !session.channels.isEmpty else {
                return .noData
            }
            let match = CircuitCatalog.identify(session)
            // A clip or a phone log with no laps of its own, at a circuit whose line is known:
            // read it again with that line, as adding it to a project would.
            if session.laps.isEmpty, let match, let line = tracks?.definition(id: match.circuit.id)?.startFinish {
                var options = SessionBuilder.Options()
                options.finishLine = FinishLine(
                    latitude: line.latitude, longitude: line.longitude, headingDegrees: line.headingDegrees,
                    halfWidthMeters: line.halfWidthMeters, headingToleranceDegrees: line.headingToleranceDegrees)
                options.ignoreFirstCrossings = line.ignoreFirstCrossings
                if let again = try? candidate.importer.importSession(at: url, options: options) { session = again }
            }
            let circuitID = match?.circuit.id
            let previous = circuitID.flatMap { id in logbook.entries().first { $0.circuitID == id } }
            let entry = try LogbookEntry.make(
                session: session, file: url, importerID: candidate.id, circuitID: circuitID,
                car: car ?? previous?.car ?? "", driver: driver ?? session.info.driverName ?? previous?.driver)
            try logbook.save(entry)
            return .added(entry)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
