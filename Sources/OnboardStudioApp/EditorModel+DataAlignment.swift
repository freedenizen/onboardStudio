import Foundation
import ProjectModel
import TelemetryKit

// MARK: - A second data file lined up with the first (#562)

extension EditorModel {
    /// The data file another is lined up with: the project's first. `nil` for that file itself, which
    /// the others are lined up with. Not `lapInput`, which follows the selection: selecting the file to
    /// line up made it the lap file, and the menu never showed (#625).
    func alignmentReference(for dataID: InputID) -> Input? {
        guard let first = project.dataInputs.first, first.id != dataID else { return nil }
        return first
    }

    /// The channels the two files both recorded, most telling first.
    func sharedRoles(_ dataID: InputID, _ referenceID: InputID) -> [ChannelRole] {
        guard let session = sessions[dataID], let reference = sessions[referenceID] else { return [] }
        return DataAlignment.sharedRoles(reference, session)
    }

    /// Slides the file along until `role` reads as it does in `referenceID`'s, as one step of Undo,
    /// and says how well it matched; a match too weak to trust is said and not applied.
    func lineUp(_ dataID: InputID, with referenceID: InputID, by role: ChannelRole) {
        guard let session = sessions[dataID], let reference = sessions[referenceID],
            let referenceInput = project.input(referenceID), let input = project.input(dataID)
        else { return }
        statusMessage = "Lining up \(input.label) by \(role.displayName.lowercased())…"
        Task { @MainActor in
            let result = await Task.detached(priority: .userInitiated) {
                DataAlignment.align(session, to: reference, by: role)
            }.value
            guard let result else {
                let channel = role.displayName.lowercased()
                statusMessage =
                    "\(input.label) and \(referenceInput.label) cannot be lined up by \(channel): one of them barely "
                    + "changes. Try another channel, or set the offset by hand."
                return
            }
            let match = String(format: "%.2f", result.score)
            guard result.isConfident else {
                statusMessage =
                    "No clear match by \(role.displayName.lowercased()) (best \(match)); nothing was moved. Try "
                    + "another channel, or set the offset by hand."
                return
            }
            let sync = SyncSettings(
                startPositionInInput: referenceInput.sync.startPositionInInput - result.offset,
                offsetInProject: referenceInput.sync.offsetInProject, playSpeed: referenceInput.sync.playSpeed)
            updateInput(dataID, name: "Line Up Data File") { $0.sync = sync }
            let shift = String(format: "%.2f", abs(result.offset))
            let word = result.offset >= 0 ? "after" : "before"
            statusMessage =
                "Lined up by \(role.displayName.lowercased()): \(input.label) begins \(shift) s \(word) "
                + "\(referenceInput.label) (match \(match))."
        }
    }
}
