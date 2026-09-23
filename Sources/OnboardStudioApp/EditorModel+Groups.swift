import Foundation
import ProjectModel

/// Multiple selection, groups and locks (#90).
extension EditorModel {
    /// Every selected object: the one the inspector shows and the rest.
    var selectedObjectIDs: Set<DisplayObjectID> {
        selectedObjectID.map { additionalSelection.union([$0]) } ?? []
    }

    var hasMultipleSelection: Bool { selectedObjectIDs.count > 1 }

    /// What a click on an object selects: on the preview, it and the rest of its group; in the
    /// sidebar, just the object, which is how one member of a group is reached to edit it. With
    /// ⌘ or ⇧ held, it is added to the selection, or taken out if it was already in it.
    func selectObject(_ id: DisplayObjectID, extending: Bool = false, wholeGroup: Bool = true) {
        let clicked = wholeGroup ? project.expandingGroups([id]) : [id]
        if extending, let primary = selectedObjectID {
            var all = selectedObjectIDs
            if clicked.isSubset(of: all) { all.subtract(clicked) } else { all.formUnion(clicked) }
            let newPrimary = all.contains(primary) ? primary : all.first
            selectedObjectID = newPrimary
            additionalSelection = newPrimary.map { all.subtracting([$0]) } ?? []
        } else {
            selectedObjectID = id
            additionalSelection = clicked.subtracting([id])
        }
        selectedInputID = nil
        selectedSegmentID = nil
        selectedMarkerID = nil
    }

    /// Moves or resizes several objects as one undo step: a group, or a multiple selection. Into
    /// the segment at the playhead when there is one, as a single object's move is.
    func moveObjects(_ frames: [DisplayObjectID: UnitRect]) {
        guard !frames.isEmpty else { return }
        edit(frames.count == 1 ? "Move Object" : "Move Objects") { project in
            for (id, frame) in frames {
                if let segment = project.timeline.segment(at: currentTime) {
                    var override = segment.overrides[id] ?? ObjectOverride()
                    override.frame = frame
                    project.timeline.setOverride(override, for: id, in: segment.id)
                } else if let index = project.displayObjects.firstIndex(where: { $0.id == id }) {
                    project.displayObjects[index].frame = frame
                }
            }
        }
    }

    /// Two or more objects not already one group.
    var canGroupSelection: Bool {
        let ids = selectedObjectIDs
        guard ids.count >= 2 else { return false }
        let groups = Set(ids.compactMap { project.displayObject($0)?.groupID })
        return !(groups.count == 1 && ids.allSatisfy { project.displayObject($0)?.groupID != nil })
    }

    var canUngroupSelection: Bool {
        selectedObjectIDs.contains { project.displayObject($0)?.groupID != nil }
    }

    func groupSelection() {
        guard canGroupSelection else { return }
        let ids = selectedObjectIDs
        edit("Group Objects") { $0.group(ids) }
    }

    func ungroupSelection() {
        guard canUngroupSelection else { return }
        let ids = selectedObjectIDs
        edit("Ungroup Objects") { $0.ungroup(ids) }
        // What was selected as a group stays selected, as separate objects.
    }

    /// Whether every selected object is locked, which is what the lock command undoes.
    var selectionIsLocked: Bool {
        let ids = selectedObjectIDs
        return !ids.isEmpty && ids.allSatisfy { project.displayObject($0)?.isLocked == true }
    }

    /// ⌘L: locks the selection, or unlocks it when it is all locked already.
    func toggleLockSelection() {
        let ids = selectedObjectIDs
        guard !ids.isEmpty else { return }
        let lock = !selectionIsLocked
        let noun = project.expandingGroups(ids).count == 1 ? "Object" : "Objects"
        edit("\(lock ? "Lock" : "Unlock") \(noun)") { $0.setLocked(lock, ids) }
    }
}
