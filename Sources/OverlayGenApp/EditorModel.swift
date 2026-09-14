import AVFoundation
import Foundation
import MediaKit
import Observation
import ProjectModel
import SwiftUI
import TelemetryKit

/// Per-window editor state: selection, playback, the compiled preview, and the edit entry points
/// the views call. Owns a `PreviewController` that keeps an `AVPlayer` in sync with the project.
@Observable
final class EditorModel {
    let document: ProjectDocument
    var fileURL: URL?
    var undoManager: UndoManager?

    var selectedObjectID: DisplayObjectID?
    var selectedInputID: InputID?
    var showSyncWizard = false
    var showExport = false
    var errorMessage: String?
    var statusMessage: String?

    let preview = PreviewController()
    private(set) var loaded: ProjectCompiler.LoadedProject?
    private var compileTask: Task<Void, Never>?
    private var lastCompiledProject: Project?

    init(document: ProjectDocument, fileURL: URL?) {
        self.document = document
        self.fileURL = fileURL
    }

    var project: Project { document.project }
    var location: ProjectLocation {
        ProjectLocation(fileURL ?? URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "Untitled.overlayproj"))
    }
    var selectedObject: DisplayObject? { selectedObjectID.flatMap(project.displayObject) }
    var selectedInput: Input? { selectedInputID.flatMap(project.input) }
    var isPlaying: Bool { preview.isPlaying }
    var currentTime: Double { preview.currentTime }
    var duration: Double { preview.duration }
    var sessions: [InputID: TelemetrySession] { loaded?.sessions ?? [:] }

    // MARK: - Editing

    func edit(_ name: String, _ change: (inout Project) -> Void) {
        document.apply(undoManager, name: name, change)
        scheduleCompile()
    }

    func addVideo() {
        guard let url = OpenPanels.chooseVideo() else { return }
        let input = Input(
            label: url.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: url, relativeTo: fileURL),
            kind: .video(VideoInputSettings()))
        edit("Add Video") { project in
            project.inputs.append(input)
            if !project.displayObjects.contains(where: {
                if case .video = $0.kind { return true } else { return false }
            }) {
                project.displayObjects.insert(
                    DisplayObject.makeDefault(kind: .video(VideoObjectParams()), inputID: input.id, index: 0), at: 0)
            }
        }
        selectedInputID = input.id
    }

    func addData() {
        guard let url = OpenPanels.chooseData() else { return }
        let input = Input(
            label: url.deletingPathExtension().lastPathComponent,
            source: MediaReference.make(for: url, relativeTo: fileURL),
            kind: .data(DataInputSettings()))
        edit("Add Data") { $0.inputs.append(input) }
        selectedInputID = input.id
    }

    func removeInput(_ id: InputID) {
        edit("Remove Input") { project in
            project.inputs.removeAll { $0.id == id }
            project.displayObjects.removeAll { $0.inputID == id }
        }
        if selectedInputID == id { selectedInputID = nil }
    }

    func addObject(_ kind: DisplayObjectKind) {
        let dataInput = project.dataInputs.first?.id
        let videoInput = project.videoInputs.first?.id
        let object = DisplayObject.makeDefault(
            kind: kind, inputID: kind.needsData ? dataInput : videoInput, index: project.displayObjects.count)
        edit("Add \(kind.typeName)") { $0.displayObjects.append(object) }
        selectedObjectID = object.id
    }

    func deleteSelectedObject() {
        guard let id = selectedObjectID else { return }
        edit("Delete Object") { $0.displayObjects.removeAll { $0.id == id } }
        selectedObjectID = nil
    }

    func updateObject(_ id: DisplayObjectID, name: String = "Edit Object", _ change: (inout DisplayObject) -> Void) {
        edit(name) { project in
            guard let index = project.displayObjects.firstIndex(where: { $0.id == id }) else { return }
            change(&project.displayObjects[index])
        }
    }

    func updateInput(_ id: InputID, name: String = "Edit Input", _ change: (inout Input) -> Void) {
        edit(name) { project in
            guard let index = project.inputs.firstIndex(where: { $0.id == id }) else { return }
            change(&project.inputs[index])
        }
    }

    func moveObject(_ id: DisplayObjectID, frame: UnitRect) {
        updateObject(id, name: "Move Object") { $0.frame = frame }
    }

    // MARK: - Playback

    func togglePlayback() { preview.togglePlayback() }
    func seek(to time: Double) { preview.seek(to: time) }
    func step(by frames: Int) { preview.seek(to: currentTime + Double(frames) / project.settings.frameRate) }

    // MARK: - Compilation

    /// Rebuilds the preview after edits. Media/data are reloaded only when inputs change;
    /// object edits just swap the overlay plan.
    func scheduleCompile() {
        compileTask?.cancel()
        let project = self.project
        let location = self.location
        let previous = loaded
        let needsRecompile = lastCompiledProject.map { ProjectCompiler.needsRecompile(from: $0, to: project) } ?? true
        compileTask = Task { [weak self] in
            guard let self else { return }
            do {
                let loaded = try await ProjectCompiler.load(project, location: location, reusing: previous)
                guard !Task.isCancelled else { return }
                self.loaded = loaded
                if needsRecompile || preview.compiled == nil {
                    let compiled = try await ProjectCompiler.compile(loaded)
                    guard !Task.isCancelled else { return }
                    preview.replace(with: compiled)
                } else if let current = preview.compiled {
                    preview.update(with: ProjectCompiler.replan(current, for: loaded))
                }
                lastCompiledProject = project
                errorMessage = nil
            } catch {
                errorMessage = "\(error)"
            }
        }
    }
}
