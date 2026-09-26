import Foundation
import ProjectModel

/// The stack of display objects (#277): the Arrange menu, the sidebar's context menu, and
/// dragging rows in the sidebar.
extension EditorModel {
    /// Off while a picture tool is open: it hides the overlays being arranged.
    func canArrangeSelection(_ move: LayerMove) -> Bool {
        pictureTool == nil && project.canArrange(selectedObjectIDs, move)
    }

    func arrangeSelection(_ move: LayerMove) {
        let ids = selectedObjectIDs
        guard canArrangeSelection(move) else { return }
        edit(move.title) { $0.arrange(ids, move) }
    }

    /// A drag in the sidebar's list, which lists the front first.
    func moveObjectsInList(_ offsets: IndexSet, to destination: Int) {
        guard pictureTool == nil else { return }
        edit("Change Layer Order") { $0.moveObjects(fromListOffsets: offsets, toListOffset: destination) }
    }
}
