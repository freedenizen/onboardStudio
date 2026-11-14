import Foundation
import Importers
import ProjectModel
import TelemetryKit

/// Projects and the logbook knowing each other (#349): a data file added to a project becomes an
/// entry (or finds the one it already has, by its bytes); the entry lists the projects and the
/// exports made from it; a file that moved is found again through whichever side still has it.
public enum ProjectLogbook {
    public struct Enrolment: Sendable {
        public let entry: LogbookEntry
        public let isNew: Bool
    }

    /// A data file added to a project, as the logbook needs to know it: the car and driver are
    /// the project's details when they are filled in.
    public struct Request: Sendable {
        public var url: URL
        public var session: TelemetrySession
        public var importerID: String?
        public var circuitID: String?
        public var car: String
        public var driver: String
        /// The lines the project times the file in runs between (#552); `nil` for laps, or to
        /// take them from the file's own gates when it has a start and a finish.
        public var runLines: RunLines?

        public init(
            url: URL, session: TelemetrySession, importerID: String? = nil, circuitID: String? = nil,
            car: String = "", driver: String = "", runLines: RunLines? = nil
        ) {
            self.runLines = runLines
            self.url = url
            self.session = session
            self.importerID = importerID
            self.circuitID = circuitID
            self.car = car
            self.driver = driver
        }
    }

    /// The entry for the request's file: the existing one with the same bytes, or of the same
    /// drive read from another file (#465), else a new one saved now.
    public static func enter(_ request: Request, into logbook: Logbook) throws -> Enrolment {
        let url = request.url
        let (hash, _) = try LogbookEntry.hash(of: url)
        if let existing = logbook.entry(forContentHash: hash) { return Enrolment(entry: existing, isNew: false) }
        let importer = request.importerID ?? (try? FormatDetector.detect(url))?.id ?? "unknown"
        let previous = request.circuitID.flatMap { id in logbook.entries().first { $0.circuitID == id } }
        var entry = try LogbookEntry.make(
            session: request.session, file: url, importerID: importer, circuitID: request.circuitID,
            car: request.car.isEmpty ? previous?.car ?? "" : request.car,
            driver: request.driver.isEmpty ? request.session.info.driverName ?? previous?.driver : request.driver)
        if let twin = logbook.entry(sameSessionAs: entry) { return Enrolment(entry: twin, isNew: false) }
        // A point-to-point course is entered in runs (#552). The project's session may still be the
        // file's first reading, before its gates were applied, so the file is read again.
        if let lines = request.runLines ?? RunLines(request.session.lapGeometry) {
            var settings = entry.readingSettings
            settings.lapLine = lines.start
            settings.runFinishLine = lines.finish
            if let session = try? ProjectCompiler.importData(at: url, settings: settings) {
                entry.readRuns(lines, of: session, among: logbook.entries())
            }
        }
        // Onto the day its date and circuit say, as a file added to the logbook itself is (#393).
        try logbook.assignDay(to: &entry)
        try logbook.save(entry)
        return Enrolment(entry: entry, isNew: true)
    }

    /// Notes the project at `url` on each entry, once.
    public static func record(project url: URL, in entryIDs: [UUID], logbook: Logbook) {
        let link = LogbookEntry.ProjectLink(path: url.path, name: url.deletingPathExtension().lastPathComponent)
        for id in entryIDs {
            guard var entry = logbook.entry(id: id), !entry.projects.contains(where: { $0.path == link.path }) else {
                continue
            }
            entry.projects.append(link)
            try? logbook.save(entry)
        }
    }

    /// Notes an exported video on each entry, once.
    public static func record(export url: URL, in entryIDs: [UUID], logbook: Logbook) {
        let link = LogbookEntry.ProjectLink(path: url.path, name: url.lastPathComponent)
        for id in entryIDs {
            guard var entry = logbook.entry(id: id), !entry.exports.contains(where: { $0.path == link.path }) else {
                continue
            }
            entry.exports.append(link)
            try? logbook.save(entry)
        }
    }

    /// Where the entry's file is now, when the project's own path no longer resolves; `nil` when
    /// the logbook has lost it too.
    public static func relinkedURL(for entryID: UUID, logbook: Logbook) -> URL? {
        logbook.entry(id: entryID)?.resolveFile()
    }

    /// The other way round: the project still has the file and the entry does not; the entry
    /// learns the new place. Returns whether anything was written.
    @discardableResult
    public static func relink(entryID: UUID, to url: URL, logbook: Logbook) -> Bool {
        guard var entry = logbook.entry(id: entryID), entry.resolveFile() == nil,
            FileManager.default.fileExists(atPath: url.path)
        else { return false }
        entry.file.path = url.path
        entry.file.bookmark =
            (try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
            ?? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        try? logbook.save(entry)
        return true
    }
}
