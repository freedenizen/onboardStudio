import Foundation
import ProjectModel

/// The stack of display objects (#277): the Arrange menu, the sidebar's context menu, and
/// dragging rows in the sidebar.
extension EditorModel {
    func canArrangeSelection(_ move: LayerMove) -> Bool { project.canArrange(selectedObjectIDs, move) }

    func arrangeSelection(_ move: LayerMove) {
        let ids = selectedObjectIDs
        guard project.canArrange(ids, move) else { return }
        edit(move.title) { $0.arrange(ids, move) }
    }

    /// A drag in the sidebar's list, which lists the front first.
    func moveObjectsInList(_ offsets: IndexSet, to destination: Int) {
        edit("Change Layer Order") { $0.moveObjects(fromListOffsets: offsets, toListOffset: destination) }
    }
}
