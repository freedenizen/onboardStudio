import ProjectModel
import SwiftUI
import TelemetryKit

extension CoachingContent {
    /// The car's grip in like conditions (#558), when the logbook knows the session.
    func carGrip(for selection: CoachingSelection) -> GripEnvelope? {
        let entryID = (source as? LogbookCoachingSource)?.entry.id ?? selection.input.dataSettings?.logbookEntryID
        guard let entry = entryID.flatMap({ id in LogbookModel.shared.entries.first { $0.id == id } }) else {
            return nil
        }
        return LogbookModel.shared.gripLimit(for: entry)?.limit
    }
}
