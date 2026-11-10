import Foundation
import ProjectModel
import TelemetryKit

/// What a compile reads from the logbook (#351): the text keys `{pb}`, `{pbDate}`, `{pbCar}`,
/// `{visits}` and `{trackDays}` (#433) for the circuit the project's data is at, and the personal-best lap's profile for a
/// timer measuring against it. Read only when the project asks (`usesLogbookKeys`,
/// `needsPersonalBest`), so a project that does not pays nothing.
public enum LogbookDerived {
    struct Result: Sendable {
        var details: [String: String] = [:]
        var personalBests: [InputID: LapProfile] = [:]
    }

    /// The key the logbook files a session under, for a data input: the one of the logbook entry
    /// the input was entered as — which is where a circuit named afterwards is kept (#455) — else
    /// the circuit the project recorded, else the one the session looks like, else the file's
    /// track name. Empty when none of them names a circuit: a file's name is not one.
    public static func circuitKey(for input: Input, session: TelemetrySession, entries: [LogbookEntry]) -> String {
        if let id = input.dataSettings?.logbookEntryID, let entry = entries.first(where: { $0.id == id }) {
            let key = LogbookFilter.circuitKey(of: entry)
            if !key.isEmpty { return key }
        }
        if let recorded = input.dataSettings?.circuitID { return recorded }
        if let match = CircuitCatalog.identify(session) { return match.circuit.id }
        return session.info.trackName?.trimmingCharacters(in: .whitespaces) ?? ""
    }

    static func make(
        for project: Project, sessions: [InputID: TelemetrySession], location: ProjectLocation, logbook: Logbook,
        previous: ProjectCompiler.LoadedProject?
    ) -> Result {
        var result = Result()
        let entries = logbook.entries()
        guard let input = project.dataInputs.first(where: { sessions[$0.id] != nil }), let session = sessions[input.id]
        else { return result }
        let url = location.resolve(input.source)
        let key = circuitKey(for: input, session: session, entries: entries)
        let car = project.details.car
        if project.usesLogbookKeys {
            result.details = PersonalBests.detailKeys(in: entries, circuitKey: key, car: car)
        }
        guard project.needsPersonalBest else { return result }
        if let previous, previous.project.details.car == car, previous.project.input(input.id) == input,
            let cached = previous.personalBests[input.id]
        {
            result.personalBests[input.id] = cached
            return result
        }
        guard
            let best = PersonalBests.best(in: entries, circuitKey: key, car: car.isEmpty ? nil : car)
                ?? PersonalBests.best(in: entries, circuitKey: key),
            let entry = logbook.entry(id: best.entryID), let file = entry.resolveFile()
        else { return result }
        // The personal best is this very session: the session best already measures it.
        if let own = try? LogbookEntry.hash(of: url).hex, own == entry.file.contentHash { return result }
        var settings = DataInputSettings()
        settings.importerID = entry.file.importerID
        guard let other = try? ProjectCompiler.importData(at: file, settings: settings),
            let lap = other.laps.first(where: { $0.number == best.lapNumber }) ?? LapDeltas.sessionBest(in: other),
            let profile = LapProfile(lap: lap, in: other)
        else { return result }
        result.personalBests[input.id] = profile
        return result
    }
}
