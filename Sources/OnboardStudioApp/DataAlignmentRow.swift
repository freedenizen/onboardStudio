import ProjectModel
import SwiftUI
import TelemetryKit

/// Line Up with… in a data file's Synchronization (#562): a second logger — an ECU log with no
/// GPS — slid along until a channel both files recorded reads the same.
struct DataAlignmentRow: View {
    let editor: EditorModel
    let input: Input

    var body: some View {
        if let reference = editor.alignmentReference(for: input.id) {
            let roles = editor.sharedRoles(input.id, reference.id)
            if roles.isEmpty {
                Text("\(input.label) and \(reference.label) record no channel in common to line them up by.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Menu("Line Up with \(reference.label)") {
                    ForEach(roles, id: \.self) { role in
                        Button("By \(role.displayName)") { editor.lineUp(input.id, with: reference.id, by: role) }
                    }
                }
                .help("Slide this file along until a channel both files recorded reads the same — RPM, else speed")
                .accessibilityIdentifier("sync.lineUp")
                Text("For a second logger whose clock disagrees: an ECU log, a CAN logger.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
