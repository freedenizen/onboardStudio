import AVFoundation
import Foundation
import Importers
import ProjectModel
import TelemetryKit

/// Reading one file of a track day, apart from filing it: what the file is, whether the logbook
/// has it, and the session or the recording as the file alone describes it.
extension TrackDayImport {
    /// What reading one file came to, before anything is filed for it: an answer already — in the
    /// logbook, not a file this app reads — or what was read.
    enum Read<Value: Sendable>: Sendable {
        case done(Filed)
        case read(Value)
    }

    /// A camera recording (#394): probed for its clock and length, then filed on its day — or kept
    /// back, when a day was chosen and the clip's clock says another (#456).
    static func importClip(_ first: URL, chapters: [URL], into logbook: Logbook, batch: Batch) async -> Filed {
        switch await probe(first, chapters: chapters, in: logbook) {
        case .done(let filed): return filed
        case .read(let clip):
            if batch.strays == .kept, let day = batch.day, let stray = Stray(clip, at: first, against: day) {
                return Filed(outcome: .waiting(stray))
            }
            return fileClipOrSayWhy(clip, first: first, into: logbook, batch: batch)
        }
    }

    /// The recording as probed, unless it is one the logbook has or a video this app made.
    static func probe(_ first: URL, chapters: [URL], in logbook: Logbook) async -> Read<ClipRecord> {
        // A video exported from a session's project, picked up with the day's folder or offered by
        // the panel beside the footage, is the finished overlay, not that session's picture (#468).
        let path = first.standardizedFileURL.path
        if let source = logbook.entries().first(where: { entry in
            entry.exports.contains { URL(fileURLWithPath: $0.path).standardizedFileURL.path == path }
        }) {
            return .done(Filed(outcome: .ownExport(source)))
        }
        do {
            let clip = try await ClipMatcher.record(first, chapters: chapters)
            if let existing = knownClip(clip, in: logbook) { return .done(Filed(outcome: .clipAlreadyThere(existing))) }
            return .read(clip)
        } catch {
            return .done(Filed(outcome: .failed(unreadableClip(first, error))))
        }
    }

    static func fileClipOrSayWhy(_ clip: ClipRecord, first: URL, into logbook: Logbook, batch: Batch) -> Filed {
        do {
            return try fileClip(clip, first: first, into: logbook, batch: batch)
        } catch {
            return Filed(outcome: .failed(unreadableClip(first, error)))
        }
    }

    /// Why a recording could not be read, about the file and what to do with it. The system's
    /// own words for an empty file are "Cannot Open", which says neither (#665).
    static func unreadableClip(_ url: URL, _ error: Error) -> String {
        if (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize == 0 {
            return "the file is empty; copy it from the camera's card again"
        }
        if (error as NSError).domain == AVFoundationErrorDomain {
            return "macOS cannot open it as a video. It may be incomplete; copy it from the camera's card again"
        }
        return error.localizedDescription
    }

    /// One telemetry file: read, then filed on its day — or kept back, when a day was chosen and
    /// the file says it is from another (#456).
    static func importOne(_ url: URL, into logbook: Logbook, batch: Batch) -> Filed {
        switch read(url, in: logbook, batch: batch) {
        case .done(let filed): return filed
        case .read(let reading):
            if batch.strays == .kept, let day = batch.day, let stray = Stray(reading, at: url, against: day) {
                // A drive the logbook has from another file is that, not a file to ask about (#465).
                if let twin = logbook.entry(sameSessionAs: reading.entry) { return Filed(outcome: .sameSession(twin)) }
                return Filed(outcome: .waiting(stray))
            }
            return file(reading, into: logbook, batch: batch)
        }
    }

    /// The session as its file alone describes it, unless the logbook has the file or it is not
    /// one this app reads.
    static func read(_ url: URL, in logbook: Logbook, batch: Batch) -> Read<Reading> {
        do {
            let (hash, _) = try LogbookEntry.hash(of: url)
            if let existing = logbook.entry(forContentHash: hash) {
                return .done(Filed(outcome: .alreadyThere(existing)))
            }
            guard let candidate = try FormatDetector.detect(url) else { return .done(Filed(outcome: .notRecognised)) }
            var session = try candidate.importer.importSession(at: url, options: SessionBuilder.Options())
            guard session[.latitude] != nil || !session.laps.isEmpty || !session.channels.isEmpty else {
                return .done(Filed(outcome: .noData))
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
            // A file that recorded a start and a finish gate is a point-to-point course: read it
            // again in runs between them (#552), as adding it to a project does.
            let lines = RunLines(session.lapGeometry)
            if let lines {
                var settings = DataInputSettings(lapLine: lines.start, runFinishLine: lines.finish)
                settings.importerID = candidate.id
                if let again = try? ProjectCompiler.importData(at: url, settings: settings) { session = again }
            }
            // Which of the circuit's configurations it drove, from where its turns are (#549), and
            // the names that configuration keeps for them, so its corners are read by their names.
            // A course timed in runs is a layout of its own, not one of a circuit's configurations.
            let kept = lines == nil ? match.map { batch.tracks?.configurations(of: $0.circuit.id) ?? [] } ?? [] : []
            let configuration = ConfigurationMatch.configuration(of: session, among: kept)
            if let definition = kept.first(where: { $0.configuration == configuration }) {
                session.turnNames = definition.turnNames
                session.cornerLabels = definition.cornerLabels
            }
            // As the file alone describes it; the day's circuit, car and driver come with the filing.
            var entry = try LogbookEntry.make(
                session: session, file: url, importerID: candidate.id, circuitID: match?.circuit.id)
            entry.configuration = configuration
            if lines != nil { entry.readRuns(lines, of: session, among: logbook.entries()) }
            return .read(Reading(entry: entry, fileDriver: session.info.driverName))
        } catch {
            return .done(Filed(outcome: .failed(error.localizedDescription)))
        }
    }
}
