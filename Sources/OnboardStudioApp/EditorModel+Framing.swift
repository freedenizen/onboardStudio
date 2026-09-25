import Foundation
import MediaKit
import ProjectModel

/// A tool that works on the picture itself, on the preview (#275, #276).
enum PictureTool: Equatable {
    /// Which part of the shot every video shows: `CameraFraming`.
    case frame
    /// What one video's own picture leaves out, and which way up it is, with the shape the crop
    /// is held to.
    case crop(InputID, aspect: CropAspect)

    var cropInput: InputID? { if case .crop(let id, _) = self { id } else { nil } }
}

/// A video's own picture settings that the crop tool changes.
struct VideoPicture: Equatable {
    var crop: CropInsets
    var rotation: Double
    var mirror: Mirror
}

/// What an open tool had when it was opened.
enum PictureToolEntry: Equatable {
    case framing(CameraFraming)
    case picture(InputID, VideoPicture)
}

/// Framing and cropping the picture on the preview (#275, #276): the preview shows the whole shot
/// with the overlays put away, the tool's rectangle is drawn over it, and a session is one undo
/// step.
extension EditorModel {
    /// What the preview plays: the project, or while a tool is open, the project with what the
    /// tool edits taken off and only its videos, so the whole picture shows and the rectangle can
    /// be drawn over it. The document itself is never changed by this; export and saving never
    /// see it.
    var previewProject: Project {
        guard let pictureTool else { return project }
        var shown = project
        shown.settings.framing = .none
        let videos = shown.displayObjects.filter { if case .video = $0.kind { true } else { false } }
        shown.displayObjects = videos
        if let id = pictureTool.cropInput {
            if let index = shown.inputs.firstIndex(where: { $0.id == id }),
                case .video(var settings) =
                    shown.inputs[index].kind
            {
                settings.crop = .none
                shown.inputs[index].kind = .video(settings)
            }
            // The camera being cropped, on its own when it has an object of its own.
            let own = videos.filter { $0.inputID == id }
            if !own.isEmpty { shown.displayObjects = own }
        }
        return shown
    }

    /// The loaded media with the document's own project in it, for exporting: what the preview
    /// has loaded may be a tool's view of it (no overlays, no framing, no crop), or a moment
    /// behind an edit. Nil while a tool is open: what is loaded then was loaded for the tool's
    /// view, without the overlays and so without, for one, the track maps' backgrounds; the ways
    /// to export are off until Done or Cancel.
    var loadedForExport: ProjectCompiler.LoadedProject? {
        guard pictureTool == nil, var loaded else { return nil }
        loaded.project = project
        return loaded
    }

    /// Exporting waits until a tool on the picture is closed (see `loadedForExport`).
    var canExport: Bool { pictureTool == nil }

    // MARK: Opening and closing

    var canFramePicture: Bool { !project.videoInputs.isEmpty && pictureTool == nil }
    var canCropPicture: Bool { cropCandidate != nil && pictureTool == nil }

    /// The video Crop Picture works on: the selected one, the one the selected object shows, the
    /// one the largest video object shows, or the first.
    var cropCandidate: InputID? {
        if let input = selectedInput, input.kind.isVideo { return input.id }
        if let object = selectedObject, case .video = object.kind, let id = object.inputID { return id }
        let videos = project.displayObjects.filter { if case .video = $0.kind { true } else { false } }
        if let largest = videos.max(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }),
            let id = largest.inputID, project.input(id)?.kind.isVideo == true
        {
            return id
        }
        return project.videoInputs.first?.id
    }

    func beginFraming() {
        guard canFramePicture else { return }
        pictureToolEntry = .framing(project.settings.framing)
        pictureTool = .frame
    }

    func beginCropping(_ id: InputID? = nil) {
        guard pictureTool == nil, let id = id ?? cropCandidate, let picture = videoPicture(of: id) else { return }
        pictureToolEntry = .picture(id, picture)
        pictureTool = .crop(id, aspect: .free)
    }

    /// Crop | Frame in the bar: what the open tool did is kept, and the other opens.
    func switchPictureTool(toCrop: Bool) {
        guard pictureTool != nil, (pictureTool?.cropInput != nil) != toCrop else { return }
        finishPictureTool()
        if toCrop { beginCropping() } else { beginFraming() }
    }

    /// Done: whatever the session did becomes one undo step.
    func finishPictureTool() {
        switch pictureToolEntry {
        case .framing(let entry):
            let final = project.settings.framing
            if final != entry {
                setFramingLive(entry)
                setFraming({ $0 = final }, name: "Reframe Videos")
            }
        case .picture(let id, let entry):
            if let final = videoPicture(of: id), final != entry {
                setVideoPictureLive(id, entry)
                updateInput(id, name: "Crop Video") { input in
                    guard case .video(var settings) = input.kind else { return }
                    settings.crop = final.crop
                    settings.rotation = final.rotation
                    settings.mirror = final.mirror
                    input.kind = .video(settings)
                }
            }
        case nil: break
        }
        pictureToolEntry = nil
        pictureTool = nil
    }

    /// Cancel or Escape: back to how it was, leaving nothing to undo.
    func cancelPictureTool() {
        switch pictureToolEntry {
        case .framing(let entry): if project.settings.framing != entry { setFramingLive(entry) }
        case .picture(let id, let entry): if videoPicture(of: id) != entry { setVideoPictureLive(id, entry) }
        case nil: break
        }
        pictureToolEntry = nil
        pictureTool = nil
    }

    /// Reset in the bar: the whole shot, or the whole picture upright and unflipped.
    func resetPictureTool() {
        switch pictureTool {
        case .frame: adjustFraming { _ in .none }
        case .crop: adjustPicture { _ in VideoPicture(crop: .none, rotation: 0, mirror: .none) }
        case nil: break
        }
    }

    // MARK: Changes while a tool is open (no undo step of their own)

    func adjustFraming(_ change: (CameraFraming) -> CameraFraming) {
        guard pictureTool == .frame else { return }
        let next = change(project.settings.framing)
        if next != project.settings.framing { setFramingLive(next) }
    }

    func adjustPicture(_ change: (VideoPicture) -> VideoPicture) {
        guard let id = pictureTool?.cropInput, let current = videoPicture(of: id) else { return }
        let next = change(current)
        if next != current { setVideoPictureLive(id, next) }
    }

    /// The shape the crop is held to; a fixed shape is applied at once, as large as it fits.
    func setCropAspect(_ aspect: CropAspect) {
        guard case .crop(let id, _) = pictureTool else { return }
        pictureTool = .crop(id, aspect: aspect)
        guard let picture = videoPicture(of: id), let pictureAspect = shownPictureAspect(of: id),
            let ratio = aspect.ratio(picture: pictureAspect)
        else { return }
        let shown = CropEditing.fitted(ratio: ratio, pictureAspect: pictureAspect)
        adjustPicture { p in
            var p = p
            p.crop = CropEditing.source(shown, rotation: picture.rotation, mirror: picture.mirror)
            return p
        }
    }

    /// Width over height of `id`'s whole picture as the preview shows it (turned, not cropped).
    func shownPictureAspect(of id: InputID) -> Double? {
        guard let info = loaded?.mediaInfo[id], let picture = videoPicture(of: id) else { return nil }
        return FramingEditing.pictureAspect(width: info.width, height: info.height, rotation: picture.rotation)
    }

    func videoPicture(of id: InputID) -> VideoPicture? {
        guard case .video(let settings) = project.input(id)?.kind else { return nil }
        return VideoPicture(crop: settings.crop, rotation: settings.rotation, mirror: settings.mirror)
    }

    func setVideoPictureLive(_ id: InputID, _ picture: VideoPicture) {
        document.apply(nil, name: "") { project in
            guard let index = project.inputs.firstIndex(where: { $0.id == id }),
                case .video(var settings) = project.inputs[index].kind
            else { return }
            settings.crop = picture.crop
            settings.rotation = picture.rotation
            settings.mirror = picture.mirror
            project.inputs[index].kind = .video(settings)
        }
        syncFromDocument()
    }

    // MARK: Names the rest of the app already uses

    func finishFraming() { finishPictureTool() }
    func cancelFraming() { cancelPictureTool() }
    func resetFramingInTool() { resetPictureTool() }
}
