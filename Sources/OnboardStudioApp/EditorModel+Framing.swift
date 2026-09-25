import Foundation
import MediaKit
import ProjectModel

/// A tool that works on the picture itself, on the preview (#275, #276).
enum PictureTool: Equatable {
    /// Which part of the shot every video shows: `CameraFraming`.
    case frame
}

/// Framing the picture on the preview (#275): the preview shows the whole shot with the overlays
/// put away, the framed window is drawn over it, and the session is one undo step.
extension EditorModel {
    /// What the preview plays: the project, or while framing, the project with its framing taken
    /// off and only its videos, so the whole shot shows and the window can be drawn over it. The
    /// document itself is never changed by this; export and saving never see it.
    var previewProject: Project {
        guard pictureTool == .frame else { return project }
        var shown = project
        shown.settings.framing = .none
        shown.displayObjects = shown.displayObjects.filter {
            if case .video = $0.kind { true } else { false }
        }
        return shown
    }

    /// The loaded media with the document's own project in it, for exporting: what the preview
    /// has loaded may be the framing view of it (no overlays, no framing), or a moment behind
    /// an edit.
    var loadedForExport: ProjectCompiler.LoadedProject? {
        guard var loaded else { return nil }
        loaded.project = project
        return loaded
    }

    var canFramePicture: Bool { !project.videoInputs.isEmpty && pictureTool == nil }

    func beginFraming() {
        guard canFramePicture else { return }
        framingAtEntry = project.settings.framing
        pictureTool = .frame
    }

    /// Done: whatever the session did becomes one undo step.
    func finishFraming() {
        guard pictureTool == .frame, let entry = framingAtEntry else { return }
        let final = project.settings.framing
        if final != entry {
            setFramingLive(entry)
            setFraming({ $0 = final }, name: "Reframe Videos")
        }
        framingAtEntry = nil
        pictureTool = nil
    }

    /// Cancel or Escape: the framing goes back to how it was, and nothing is left to undo.
    func cancelFraming() {
        guard pictureTool == .frame, let entry = framingAtEntry else { return }
        if project.settings.framing != entry { setFramingLive(entry) }
        framingAtEntry = nil
        pictureTool = nil
    }

    /// Changes the framing while the tool is open, without an undo step of its own.
    func adjustFraming(_ change: (CameraFraming) -> CameraFraming) {
        guard pictureTool == .frame else { return }
        let next = change(project.settings.framing)
        if next != project.settings.framing { setFramingLive(next) }
    }

    func resetFramingInTool() { adjustFraming { _ in .none } }
}
