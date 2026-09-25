import ProjectModel

/// What the editor shows at the playhead, followed at segment boundaries rather than on every
/// tick of playback (#279).
extension EditorModel {
    /// The segment in effect at the playhead: visibility, position and opacity edits go there.
    var editingSegment: Segment? { project.timeline.segment(at: playheadResolutionTime) }
    /// Objects as they appear at the playhead.
    var resolvedObjects: [DisplayObject] { project.displayObjects(at: playheadResolutionTime) }
    /// One object as it appears at the playhead, without resolving all the others: the sidebar
    /// asks this once per row.
    func resolvedObject(_ id: DisplayObjectID) -> DisplayObject? {
        project.displayObject(id).map { project.timeline.resolve([$0], at: playheadResolutionTime)[0] }
    }

    /// Called on every move of the playhead and every change to the project; writes only when the
    /// segment in effect changes, so nothing that reads it redraws in between.
    func followPlayhead() {
        let time = project.timeline.resolutionTime(at: currentTime)
        if time != playheadResolutionTime { playheadResolutionTime = time }
    }
}
