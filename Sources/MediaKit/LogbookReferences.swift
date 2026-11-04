import Foundation
import ProjectModel
import TelemetryKit

/// Logbook sessions as coaching references (#352): the sessions at the same circuit as the lap
/// being read, the personal best among them, the last visit, and reading one in on demand.
public enum LogbookReferences {
    /// The logbook's key for the session a project is reading.
    public static func circuitKey(for input: Input, session: TelemetrySession, url: URL) -> String {
        LogbookDerived.circuitKey(for: input, session: session, url: url)
    }

    /// Sessions at `circuitKey` other than the one being read (`ownHash`, when known), newest first.
    public static func sessions(
        at circuitKey: String, in entries: [LogbookEntry], excluding ownHash: String? = nil
    ) -> [LogbookEntry] {
        entries.filter {
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
        var parts = [entry.title]
        if let date = entry.date { parts.append(date.formatted(date: .abbreviated, time: .omitted)) }
        if let lap = lap ?? entry.bestLapNumber { parts.append("lap \(lap)") }
        return parts.joined(separator: ", ")
    }

    /// The entry's session, read with the importer that read it first; `nil` when its file is
    /// gone or unreadable.
    public static func load(_ entry: LogbookEntry) -> TelemetrySession? {
        guard let url = entry.resolveFile() else { return nil }
        var settings = DataInputSettings()
        settings.importerID = entry.file.importerID
        return try? ProjectCompiler.importData(at: url, settings: settings)
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
