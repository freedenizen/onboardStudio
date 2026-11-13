import Foundation
import ProjectModel
import TelemetryKit

/// Logbook sessions as coaching references (#352): the sessions at the same circuit as the lap
/// being read, the personal best among them, the last visit, and reading one in on demand.
public enum LogbookReferences {
    /// The logbook's key for the session a project is reading.
    public static func circuitKey(for input: Input, session: TelemetrySession, entries: [LogbookEntry]) -> String {
        LogbookDerived.circuitKey(for: input, session: session, entries: entries)
    }

    /// Sessions at `circuitKey` other than the one being read (`ownHash`, when known), newest first.
    public static func sessions(
        at circuitKey: String, in entries: [LogbookEntry], excluding ownHash: String? = nil
    ) -> [LogbookEntry] {
        // Sessions that name no circuit are not at one place (#455): none is a reference for another.
        guard !circuitKey.isEmpty else { return [] }
        return entries.filter {
            LogbookFilter.circuitKey(of: $0) == circuitKey && $0.bestLap != nil && $0.file.contentHash != ownHash
        }
    }

    /// The personal best among `candidates` (the quickest complete lap), and the last visit (the
    /// newest dated session); `nil` where there is none.
    public static func personalBest(in candidates: [LogbookEntry]) -> LogbookEntry? {
        candidates.min { ($0.bestLap ?? .infinity) < ($1.bestLap ?? .infinity) }
    }

    public static func lastVisit(in candidates: [LogbookEntry]) -> LogbookEntry? {
        candidates.filter { $0.date != nil }.max { ($0.date ?? .distantPast) < ($1.date ?? .distantPast) }
    }

    /// "Sonoma, 23 Aug 2026, lap 4": how the reading names the reference.
    public static func phrase(for entry: LogbookEntry, lap: Int?) -> String {
        var parts = [entry.circuitTitle]
        if let date = entry.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        if let lap = lap ?? entry.bestLapNumber { parts.append("lap \(lap)") }
        return parts.joined(separator: ", ")
    }

    /// The entry's session, read with the importer that read it first; `nil` when its file is
    /// gone or unreadable.
    ///
    /// With `tracks`, the session has the turn names its configuration keeps (#549), so its
    /// corners are read and coached by their names as they were when it was entered.
    public static func load(_ entry: LogbookEntry, tracks: TrackLibrary? = nil) -> TelemetrySession? {
        guard let url = entry.resolveFile() else { return nil }
        var settings = DataInputSettings()
        settings.importerID = entry.file.importerID
        if let tracks, entry.circuitID != nil,
            let definition = tracks.definition(id: LogbookFilter.circuitKey(of: entry))
        {
            settings.turnNames = definition.turnNames
            settings.cornerLabels = definition.cornerLabels
        }
        return try? ProjectCompiler.importData(at: url, settings: settings)
    }

    /// Reads again the files of the entries that were read before a correction to their laps
    /// (#498), and writes what the laps come to now — the laps, the best, optimal and fastest
    /// rolling lap, the best lap's corners — leaving everything the driver wrote. Returns the ids
    /// of those whose file could not be found or read; they are left as they were.
    public static func readLapsAgain(of ids: [UUID], in logbook: Logbook) -> [UUID] {
        var unread: [UUID] = []
        for id in ids {
            guard var entry = logbook.entry(id: id), entry.needsLapReading else { continue }
            guard let session = load(entry) else {
                unread.append(id)
                continue
            }
            entry.readLaps(of: session)
            try? logbook.save(entry)
        }
        return unread
    }

    /// The reference lap's profile: `lap` of the entry's session, else its best lap.
    public static func profile(of entry: LogbookEntry, lap: Int?, session: TelemetrySession) -> LapProfile? {
        let number = lap ?? entry.bestLapNumber
        guard
            let chosen = session.laps.first(where: { $0.number == number && $0.isComplete })
                ?? LapDeltas.sessionBest(in: session)
        else { return nil }
        return LapProfile(lap: chosen, in: session)
    }
}
