import ProjectModel
import SwiftUI

/// Several objects selected at once — a group, or a ⌘-click selection (#90): what can be done to
/// all of them together, and a way to any one of them.
struct MultipleSelectionInspector: View {
    @Bindable var editor: EditorModel

    var objects: [DisplayObject] {
        editor.project.displayObjects.reversed().filter { editor.selectedObjectIDs.contains($0.id) }
    }

    var isOneGroup: Bool {
        let groups = Set(objects.map(\.groupID))
        return groups.count == 1 && groups.first.flatMap(\.self) != nil
    }

    var body: some View {
        Section(isOneGroup ? "Group of \(objects.count)" : "\(objects.count) Objects") {
            ForEach(objects) { object in
                Button(object.label) { editor.selectObject(object.id, wholeGroup: false) }
                    .buttonStyle(.link)
                    .help("Select only \(object.label), to edit it on its own")
            }
            Text(
                isOneGroup
                    ? "They move, resize and nudge as one. Choose one to edit it on its own."
                    : "Drag or nudge any of them to move them all together."
            )
            .font(.caption).foregroundStyle(.secondary)
        }
        Section {
            if editor.canGroupSelection {
                Button("Group") { editor.groupSelection() }.accessibilityIdentifier("selection.group")
            }
            if editor.canUngroupSelection {
                Button("Ungroup") { editor.ungroupSelection() }.accessibilityIdentifier("selection.ungroup")
            }
            Button(editor.selectionIsLocked ? "Unlock" : "Lock") { editor.toggleLockSelection() }
                .accessibilityIdentifier("selection.lock")
            Button("Delete Objects", role: .destructive) { editor.deleteSelectedObject() }
                .disabled(editor.selectionIsLocked)
        }
    }
}
