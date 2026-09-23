import Foundation
import OSLog
import ProjectModel
import TelemetryKit

/// What the app did, written where Console can show it and a diagnostics bundle can carry it
/// (#152). One subsystem, a category per kind of work.
public enum Diagnostics {
    public static let subsystem = "com.freedenizen.onboardstudio"
    public static let importing = Logger(subsystem: subsystem, category: "import")
    public static let exporting = Logger(subsystem: subsystem, category: "export")
    /// What the app told the user: status messages and errors, as the activity log lists them.
    public static let activity = Logger(subsystem: subsystem, category: "activity")

    /// Logs what was read from `url` and hands the session back, so logging costs the caller no
    /// extra line.
    static func imported(_ session: TelemetrySession, from url: URL) -> TelemetrySession {
        let summary =
            "\(url.lastPathComponent): \(session.info.sourceFormat), \(session.channels.count) channels, "
            + "\(session.laps.count) laps, \(String(format: "%.1f", session.duration)) s"
        importing.info("Read \(summary, privacy: .public)")
        return session
    }

    static func exportStarted(_ name: String, _ settings: ExportSettings) {
        let summary = "\(name): \(settings.width)×\(settings.height) at \(settings.frameRate) fps"
        exporting.info("Exporting \(summary, privacy: .public)")
    }

    static func exportFailed(_ name: String, _ error: any Error) {
        let summary = "\(name): \(String(describing: error))"
        exporting.error("Export failed \(summary, privacy: .public)")
    }

    /// Logs why `url` could not be loaded and returns the problem as the input reports it.
    static func failedToLoad(_ url: URL, _ error: any Error) -> String {
        let problem = "\(error)"
        let file = url.lastPathComponent
        importing.error("Could not load \(file, privacy: .public): \(problem, privacy: .public)")
        return problem
    }

    /// This process's log lines since `date`, oldest first, one per line. Empty rather than an
    /// error when the log store cannot be read: a bundle without the log still helps.
    public static func logText(since date: Date) -> String {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier),
            let entries = try? store.getEntries(
                at: store.position(date: date), matching: NSPredicate(format: "subsystem == %@", subsystem))
        else { return "" }
        return entries.compactMap { $0 as? OSLogEntryLog }
            .map { "\($0.date.formatted(.iso8601)) [\($0.category)] \($0.composedMessage)" }
            .joined(separator: "\n")
    }

    /// Writes `files` — names to contents — into a zip at `url`, inside a folder named for it, and
    /// replaces anything already there.
    public static func writeBundle(_ files: [String: Data], to url: URL) throws {
        let folderName = url.deletingPathExtension().lastPathComponent
        let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let folder = scratch.appending(path: folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }
        for (name, data) in files {
            let file = folder.appending(path: name)
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: file)
        }
        // Coordinated reading "for uploading" hands back a zip of the folder: Finder's own
        // Compress, without shelling out to ditto.
        var failure: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: folder, options: .forUploading, error: &failure) { zip in
            do {
                if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
                try FileManager.default.copyItem(at: zip, to: url)
            } catch {
                copyError = error
            }
        }
        if let failure { throw failure }
        if let copyError { throw copyError }
    }

    /// Crash reports this app has left in the last `days` days, newest first.
    public static func crashReports(
        within days: Double = 14,
        in folder: URL = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Logs/DiagnosticReports")
    ) -> [URL] {
        let cutoff = Date().addingTimeInterval(-days * 86_400)
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return
            files
            .filter { $0.lastPathComponent.hasPrefix("OnboardStudio") && ["ips", "crash"].contains($0.pathExtension) }
            .compactMap { url -> (URL, Date)? in
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
                guard let date = values?.contentModificationDate, date > cutoff
                else { return nil }
                return (url, date)
            }
            .sorted { $0.1 > $1.1 }
            .map(\.0)
    }
}
