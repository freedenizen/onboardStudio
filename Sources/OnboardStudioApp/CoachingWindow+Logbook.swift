import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit

// Kept out of `CoachingContent`'s body, which SwiftLint holds to 250 lines.
extension CoachingContent {
    // MARK: - Choosing

    func setLap(_ number: Int, selection: CoachingSelection) {
        var settings = selection.settings
        settings.lap = number
        source.setSettings(settings, undoName: "Change Coaching Lap")
    }

    func setReference(_ reference: CoachingSettings.Reference, selection: CoachingSelection) {
        var settings = selection.settings
        settings.reference = reference
        source.setSettings(settings, undoName: "Change Coaching Reference")
    }

    func setAlignByPosition(_ byPosition: Bool, selection: CoachingSelection) {
        var settings = selection.settings
        settings.alignByPosition = byPosition
        source.setSettings(settings, undoName: "Change Coaching Alignment")
    }

    /// The logbook's sessions at this circuit (#352): the personal best and the last visit first,
    /// then every one by date and car. Nothing when the logbook has none here.
    @ViewBuilder
    func logbookChoices(selection: CoachingSelection) -> some View {
        let candidates = logbookCandidates(for: selection)
        if !candidates.isEmpty {
            Section("Logbook") {
                if let best = LogbookReferences.personalBest(in: candidates) {
                    Text("Personal best here — \(LogbookReferences.phrase(for: best, lap: nil))")
                        .tag(CoachingSettings.Reference.logbook(entryID: best.id, lap: nil))
                }
                if let last = LogbookReferences.lastVisit(in: candidates),
                    last.id != LogbookReferences.personalBest(in: candidates)?.id
                {
                    Text("Last visit — \(LogbookReferences.phrase(for: last, lap: nil))")
                        .tag(CoachingSettings.Reference.logbook(entryID: last.id, lap: nil))
                }
                ForEach(candidates) { entry in
                    Text(Self.candidateTitle(entry))
                        .tag(CoachingSettings.Reference.logbook(entryID: entry.id, lap: entry.bestLapNumber))
                }
            }
        }
    }

    /// "Sonoma, 23 Aug 2026, lap 4 · Miata".
    static func candidateTitle(_ entry: LogbookEntry) -> String {
        [LogbookReferences.phrase(for: entry, lap: nil), entry.car].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    /// Whether the reference is another session, which is always matched by position.
    static func isAlwaysByPosition(_ reference: CoachingSettings.Reference) -> Bool {
        switch reference {
        case .otherInput, .logbook: true
        default: false
        }
    }

    func logbookCandidates(for selection: CoachingSelection) -> [LogbookEntry] {
        guard let session = source.session else { return [] }
        let key = source.circuitKey(for: session)
        return LogbookReferences.sessions(at: key, in: LogbookModel.shared.entries, excluding: source.ownContentHash)
    }
}
