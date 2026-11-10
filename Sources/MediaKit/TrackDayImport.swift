import Foundation
import Importers
import ProjectModel
import TelemetryKit

/// A track day into the logbook (#346): every recognised telemetry file and every camera clip with
/// embedded GPS among the files and folders given becomes an entry; a file already there (same
/// bytes) is skipped, and so is a session already there from another file (#465: the same drive
/// exported in a second format); each file gets a line in the user's words.
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
    }

    public struct Report: Sendable {
        public let url: URL
        public let outcome: Outcome
        /// The day the session was put on when none was chosen (#393): "23 Aug 2026 · Sonoma".
        public let dayLabel: String?

        public init(url: URL, outcome: Outcome, dayLabel: String? = nil) {
            self.url = url
            self.outcome = outcome
            self.dayLabel = dayLabel
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

        /// "session_3.csv — added: Sonoma, 12 laps, best 1:56.88", and ", in 23 Aug 2026 · Sonoma"
        /// when the day was found for it rather than chosen.
        public var line: String {
            let name = url.lastPathComponent
            switch outcome {
            case .added(let entry):
                let day = dayLabel.map { ", in \($0)" } ?? ""
                return "\(name) — added: \(Self.describe(entry))\(day)"
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
    /// file says. `progress` is told the index, the count and the file before each one.
    public static func run(
        _ urls: [URL], into logbook: Logbook, tracks: TrackLibrary? = nil, car: String? = nil, driver: String? = nil,
        day: TrackDay? = nil, progress: @Sendable (Int, Int, URL) -> Void = { _, _, _ in }
    ) async -> [Report] {
        let files = files(in: urls)
        let clips = CameraChapters.group(files.filter(ClipMatcher.isClip))
        let telemetry = files.filter { !ClipMatcher.isClip($0) }
        let count = telemetry.count + clips.count
        let batch = Batch(tracks: tracks, car: car, driver: driver, day: day)
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
            reports.append(report(outcome, for: first, chosen: day, logbook: logbook))
        }
        return reports
    }

    /// What one Add Track Day… was told: the track library to read lines from, the car and
    /// driver for every file, and the day they go on when one was chosen.
    struct Batch: Sendable {
        var tracks: TrackLibrary?
        var car: String?
        var driver: String?
        var day: TrackDay?
    }

    /// The report for an outcome, naming the day a session was put on when none was chosen.
    static func report(_ outcome: Outcome, for url: URL, chosen day: TrackDay?, logbook: Logbook) -> Report {
        var label: String?
        if day == nil, case .added(let entry) = outcome, let id = entry.trackDayID {
            label = logbook.day(id: id)?.label
        }
        return Report(url: url, outcome: outcome, dayLabel: label)
    }

    /// A camera recording onto its day (#394): probed for its clock and length, matched against
    /// the day's sessions; a clip with GPS that matches none is read as a session of its own
    /// first, as it was before days existed, and is then the picture of that session.
    static func importClip(_ first: URL, chapters: [URL], into logbook: Logbook, batch: Batch) async -> Outcome {
        let chosen = batch.day
        // A video exported from a session's project, picked up with the day's folder or offered by
        // the panel beside the footage, is the finished overlay, not that session's picture (#468).
        let path = first.standardizedFileURL.path
        if let source = logbook.entries().first(where: { entry in
            entry.exports.contains { URL(fileURLWithPath: $0.path).standardizedFileURL.path == path }
        }) {
            return .ownExport(source)
        }
        do {
            var clip = try await ClipMatcher.record(first, chapters: chapters)
            if let known = logbook.days().first(where: { $0.clips.contains { $0.fingerprint == clip.fingerprint } }),
                let existing = known.clips.first(where: { $0.fingerprint == clip.fingerprint })
            {
                return .clipAlreadyThere(existing)
            }
            var day: TrackDay
            var sessions: [LogbookEntry]
            if let chosen {
                day = logbook.day(id: chosen.id) ?? chosen
                sessions = logbook.sessions(of: day)
            } else {
                // The day the clock says, among the days with sessions then; else one of its own.
                let date = clip.recordedAt ?? Date()
                day = try logbook.day(on: date, car: batch.car ?? "", driver: batch.driver ?? "")
                sessions = logbook.sessions(of: day)
            }
            var matched = ClipMatcher.match(clip, to: sessions)
            var onDay = batch
            onDay.day = day
            if matched == nil, clip.hasGPS, case .added(let own) = importOne(first, into: logbook, batch: onDay) {
                matched = (own.id, .clock)
                sessions.append(own)
            }
            clip.sessionID = matched?.id
            clip.matchedBy = matched?.by
            day = logbook.day(id: day.id) ?? day
            day.clips.append(clip)
            try logbook.saveDay(day)
            return .clip(clip, session: matched.flatMap { id, _ in sessions.first { $0.id == id } })
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    static func importOne(_ url: URL, into logbook: Logbook, batch: Batch) -> Outcome {
        let (tracks, car, driver, day) = (batch.tracks, batch.car, batch.driver, batch.day)
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
            let circuitID = match?.circuit.id ?? day?.circuitID
            let previous = circuitID.flatMap { id in logbook.entries().first { $0.circuitID == id } }
            let dayCar = day.flatMap { $0.car.isEmpty ? nil : $0.car }
            let dayDriver = day.flatMap { $0.driver.isEmpty ? nil : $0.driver }
            var entry = try LogbookEntry.make(
                session: session, file: url, importerID: candidate.id, circuitID: circuitID,
                car: car ?? dayCar ?? previous?.car ?? "",
                driver: driver ?? dayDriver ?? session.info.driverName ?? previous?.driver)
            // The same drive from another file — RaceChrono's CSV beside its .rcz — is not a second
            // session (#465). Before the day, so a refused file makes no day either.
            if let twin = logbook.entry(sameSessionAs: entry) { return .sameSession(twin) }
            if let day {
                // Onto the chosen day, with its conditions as the session's to begin with.
                entry.trackDayID = day.id
                if entry.conditions.isEmpty { entry.conditions = day.conditions }
            } else {
                entry.trackDayID = try logbook.day(for: entry).id
            }
            try logbook.save(entry)
            return .added(entry)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
