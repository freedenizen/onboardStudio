import Foundation
import Importers
import ProjectModel
import TelemetryKit

/// A track day into the logbook (#346): every recognised telemetry file and every camera clip with
/// embedded GPS among the files and folders given becomes an entry; a file already there (same
/// bytes) is skipped, and so is a session already there from another file (#465: the same drive
/// exported in a second format); each file gets a line in the user's words. A file that is not
/// from the day chosen for it can be kept back until the user says where it goes (#456).
public enum TrackDayImport {
    public enum Outcome: Sendable, Equatable {
        case added(LogbookEntry)
        case alreadyThere(LogbookEntry)
        /// The drive is in the logbook from another file — another export format (#465).
        case sameSession(LogbookEntry)
        case notRecognised
        case noData
        case failed(String)
        /// A camera clip kept on the day (#394), with the session it was matched to, if any.
        case clip(ClipRecord, session: LogbookEntry?)
        case clipAlreadyThere(ClipRecord)
        /// A video this app exported from the session's project (#468): not a camera recording.
        case ownExport(LogbookEntry)
        /// Read for a chosen day and not from it (#456): not in the logbook until `place` is told
        /// where.
        case waiting(Stray)
    }

    public struct Report: Sendable {
        public let url: URL
        public let outcome: Outcome
        /// The day the session was put on when none was chosen (#393): "23 Aug 2026 · Sonoma".
        public let dayLabel: String?
        /// What the chosen day decided for a session added to it (#456): its circuit when the
        /// file had none, its date in spite of the file's. Said in the line, after the session.
        public let notes: [String]

        public init(url: URL, outcome: Outcome, dayLabel: String? = nil, notes: [String] = []) {
            self.url = url
            self.outcome = outcome
            self.dayLabel = dayLabel
            self.notes = notes
        }

        public var isAdded: Bool { if case .added = outcome { return true } else { return false } }
        /// The session was in the logbook already: this file, or the same drive from another.
        public var isAlreadyThere: Bool {
            switch outcome {
            case .alreadyThere, .sameSession: true
            default: false
            }
        }
        public var isClip: Bool {
            switch outcome {
            case .clip, .clipAlreadyThere: true
            default: false
            }
        }
        /// Kept back until the user says where it goes (#456).
        public var isWaiting: Bool { if case .waiting = outcome { return true } else { return false } }

        /// "session_3.csv — added: Sonoma, 12 laps, best 1:56.88", and ", in 23 Aug 2026 · Sonoma"
        /// when the day was found for it rather than chosen.
        public var line: String {
            let name = url.lastPathComponent
            switch outcome {
            case .added(let entry):
                let day = dayLabel.map { ", in \($0)" } ?? ""
                let noted = notes.isEmpty ? "" : " (\(notes.joined(separator: "; ")))"
                return "\(name) — added: \(Self.describe(entry))\(day)\(noted)"
            case .alreadyThere(let entry): return "\(name) — already in the logbook as \(Self.describe(entry))"
            case .sameSession(let entry):
                let file = URL(fileURLWithPath: entry.file.path).lastPathComponent
                return "\(name) — the same session as \(file), already in the logbook: \(Self.describe(entry))"
            case .notRecognised: return "\(name) — not a telemetry file this app reads"
            case .noData: return "\(name) — no position or laps in it"
            case .failed(let reason): return "\(name) — could not be read: \(reason)"
            case .clip(let clip, let session):
                let span = ClipMatcher.describe(clip)
                let what = span.isEmpty ? "video" : "video, \(span)"
                if let session {
                    return "\(name) — \(what): the picture of \(Self.describe(session))"
                }
                return "\(name) — \(what): no session at that time, assign it in the logbook"
            case .clipAlreadyThere: return "\(name) — video already on the day"
            case .ownExport(let entry):
                return "\(name) — not added: a video exported from \(Self.describe(entry)), not a recording"
            case .waiting(let stray): return "\(name) — not added yet: \(stray.reason)"
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

    /// Imports every file into `logbook`, onto `day` when one was chosen (#393), else each onto
    /// the day its date and circuit say (`Logbook.day(for:)`). `car` for the whole batch, else the
    /// day's, else the last session at the same circuit's car; `driver` likewise, else what the
    /// file says. With `strays: .kept`, a file that is not from the chosen day is read and kept
    /// back for `place` (#456). `progress` is told the index, the count and the file before each one.
    public static func run(
        _ urls: [URL], into logbook: Logbook, tracks: TrackLibrary? = nil, car: String? = nil, driver: String? = nil,
        day: TrackDay? = nil, strays: Strays = .ontoTheDay,
        progress: @Sendable (Int, Int, URL) -> Void = { _, _, _ in }
    ) async -> [Report] {
        let files = files(in: urls)
        let clips = CameraChapters.group(files.filter(ClipMatcher.isClip))
        let telemetry = files.filter { !ClipMatcher.isClip($0) }
        let count = telemetry.count + clips.count
        let batch = Batch(tracks: tracks, car: car, driver: driver, day: day, strays: strays)
        var reports: [Report] = []
        for (index, url) in telemetry.enumerated() {
            progress(index, count, url)
            reports.append(report(importOne(url, into: logbook, batch: batch), for: url, chosen: day, logbook: logbook))
            await Task.yield()
        }
        // The clips after the sessions, so a clip and its log in one batch pair up (#394).
        for (index, group) in clips.enumerated() {
            guard let first = group.first else { continue }
            progress(telemetry.count + index, count, first)
            let outcome = await importClip(first, chapters: Array(group.dropFirst()), into: logbook, batch: batch)
            reports.append(report(Filed(outcome: outcome), for: first, chosen: day, logbook: logbook))
        }
        return reports
    }

    /// What one Add Track Day… was told: the track library to read lines from, the car and
    /// driver for every file, the day they go on when one was chosen, and what becomes of a file
    /// that is not from that day.
    struct Batch: Sendable {
        var tracks: TrackLibrary?
        var car: String?
        var driver: String?
        var day: TrackDay?
        var strays = Strays.ontoTheDay
    }

    /// What became of one file, and whether a session added took the day's circuit for want of
    /// one of its own — which the entry alone cannot say.
    struct Filed: Sendable {
        var outcome: Outcome
        var tookDayCircuit = false
    }

    /// The report for an outcome: naming the day a session was put on when none was chosen, and
    /// saying what a chosen day decided for it (#456) — the circuit, or the date.
    static func report(_ filed: Filed, for url: URL, chosen day: TrackDay?, logbook: Logbook) -> Report {
        var label: String?
        var notes: [String] = []
        if case .added(let entry) = filed.outcome {
            if let day {
                if filed.tookDayCircuit { notes.append("no circuit recognised in the file, so the day's") }
                if let date = entry.date, TrackDay.startOfDay(date) != day.date {
                    notes.append("dated another day than this one")
                }
            } else if let id = entry.trackDayID {
                label = logbook.day(id: id)?.label
            }
        }
        return Report(url: url, outcome: filed.outcome, dayLabel: label, notes: notes)
    }

    /// A camera recording (#394): probed for its clock and length, then filed on its day — or kept
    /// back, when a day was chosen and the clip's clock says another (#456).
    static func importClip(_ first: URL, chapters: [URL], into logbook: Logbook, batch: Batch) async -> Outcome {
        // A video exported from a session's project, picked up with the day's folder or offered by
        // the panel beside the footage, is the finished overlay, not that session's picture (#468).
        let path = first.standardizedFileURL.path
        if let source = logbook.entries().first(where: { entry in
            entry.exports.contains { URL(fileURLWithPath: $0.path).standardizedFileURL.path == path }
        }) {
            return .ownExport(source)
        }
        do {
            let clip = try await ClipMatcher.record(first, chapters: chapters)
            if let existing = knownClip(clip, in: logbook) { return .clipAlreadyThere(existing) }
            if batch.strays == .kept, let day = batch.day, let stray = Stray(clip, at: first, against: day) {
                return .waiting(stray)
            }
            return try fileClip(clip, first: first, into: logbook, batch: batch)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    /// One telemetry file: read, then filed on its day — or kept back, when a day was chosen and
    /// the file says it is from another (#456).
    static func importOne(_ url: URL, into logbook: Logbook, batch: Batch) -> Filed {
        do {
            let (hash, _) = try LogbookEntry.hash(of: url)
            if let existing = logbook.entry(forContentHash: hash) { return Filed(outcome: .alreadyThere(existing)) }
            guard let candidate = try FormatDetector.detect(url) else { return Filed(outcome: .notRecognised) }
            var session = try candidate.importer.importSession(at: url, options: SessionBuilder.Options())
            guard session[.latitude] != nil || !session.laps.isEmpty || !session.channels.isEmpty else {
                return Filed(outcome: .noData)
            }
            let match = CircuitCatalog.identify(session)
            // A clip or a phone log with no laps of its own, at a circuit whose line is known:
            // read it again with that line, as adding it to a project would.
            if session.laps.isEmpty, let match, let line = batch.tracks?.definition(id: match.circuit.id)?.startFinish {
                var options = SessionBuilder.Options()
                options.finishLine = FinishLine(
                    latitude: line.latitude, longitude: line.longitude, headingDegrees: line.headingDegrees,
                    halfWidthMeters: line.halfWidthMeters, headingToleranceDegrees: line.headingToleranceDegrees)
                options.ignoreFirstCrossings = line.ignoreFirstCrossings
                if let again = try? candidate.importer.importSession(at: url, options: options) { session = again }
            }
            // As the file alone describes it; the day's circuit, car and driver come with the filing.
            let entry = try LogbookEntry.make(
                session: session, file: url, importerID: candidate.id, circuitID: match?.circuit.id)
            let reading = Reading(entry: entry, fileDriver: session.info.driverName)
            if batch.strays == .kept, let day = batch.day, let stray = Stray(reading, at: url, against: day) {
                // A drive the logbook has from another file is that, not a file to ask about (#465).
                if let twin = logbook.entry(sameSessionAs: entry) { return Filed(outcome: .sameSession(twin)) }
                return Filed(outcome: .waiting(stray))
            }
            return file(reading, into: logbook, batch: batch)
        } catch {
            return Filed(outcome: .failed(error.localizedDescription))
        }
    }
}
