import Foundation
import ProjectModel
import TelemetryKit

/// Builds the coaching track of every data input for a compile (#323): each input's laps
/// against the project's coaching reference, or the session's best lap when the project has not
/// chosen one; a reference from another input is read across sessions.
enum CoachingTracks {
    static func make(
        for project: Project, sessions: [InputID: TelemetrySession], previous: ProjectCompiler.LoadedProject?
    ) -> [InputID: CoachingTrack] {
        var tracks: [InputID: CoachingTrack] = [:]
        let settings = project.coaching
        // The notes are written in the app's speed unit: mph gives mph and feet, the rest km/h
        // and metres. The same reading the Coaching window makes.
        let appSpeedUnit =
            SpeedUnitSetting(rawValue: UserDefaults.standard.value(for: Preferences.speedUnit)) ?? .automatic
        let units = CoachingUnits.following(appSpeedUnit, legacyAutomatic: project.settings.legacyAutomaticUnits)
        for input in project.dataInputs {
            guard let session = sessions[input.id] else { continue }
            // Reuse when nothing it was read from changed: the inputs, their sessions and the
            // chosen reference. A session object is replaced on re-import, so identity is enough.
            if let previous, previous.project.coaching == settings, previous.project.inputs == project.inputs,
                let cached = previous.coaching[input.id], previous.sessions[input.id]?.laps == session.laps,
                previous.sessions[input.id]?.duration == session.duration
            {
                tracks[input.id] = cached
                continue
            }
            let own = settings?.dataInputID == input.id ? settings : nil
            let reference = own?.reference ?? .sessionBest
            var options = CoachingOptions()
            if own?.alignByPosition == true { options.alignment = .byPosition }
            let track: CoachingTrack?
            switch reference {
            case .sessionBest:
                track = CoachingTrack.make(session: session, reference: .sessionBest, units: units, options: options)
            case .lap(let number):
                track = CoachingTrack.make(session: session, reference: .lap(number), units: units, options: options)
            case .fastestRolling:
                track = CoachingTrack.make(session: session, reference: .fastestRolling, units: units, options: options)
            case .compositeOptimal:
                track = CoachingTrack.make(
                    session: session, reference: .compositeOptimal, units: units, options: options)
            case .otherInput(let id, let number):
                guard let other = sessions[id], let otherInput = project.input(id),
                    let lap = other.laps.first(where: { $0.number == number }),
                    let profile = LapProfile(lap: lap, in: other)
                else {
                    track = CoachingTrack.make(session: session, reference: .sessionBest, units: units)
                    break
                }
                track = CoachingTrack.make(
                    session: session, reference: profile, referencePhrase: "\(otherInput.label) lap \(number)",
                    sameSession: false, units: units, options: options)
            case .logbook(let entryID, let number):
                let logbook = Logbook(directory: ProjectCompiler.effectiveLogbookDirectory)
                guard let entry = logbook.entry(id: entryID), let other = LogbookReferences.load(entry),
                    let profile = LogbookReferences.profile(of: entry, lap: number, session: other)
                else {
                    track = CoachingTrack.make(session: session, reference: .sessionBest, units: units)
                    break
                }
                track = CoachingTrack.make(
                    session: session, reference: profile,
                    referencePhrase: LogbookReferences.phrase(for: entry, lap: number), sameSession: false,
                    units: units, options: options)
            }
            if let track { tracks[input.id] = track }
        }
        return tracks
    }
}
