import ProjectModel
import SwiftUI
import UniformTypeIdentifiers

@main
struct OverlayGenApp: App {
    @State private var updater = UpdaterModel()

    var body: some Scene {
        DocumentGroup(
            newDocument: { ProjectDocument() },
            editor: { file in
                EditorView(document: file.document, fileURL: file.fileURL)
                    .environment(updater)
            }
        )
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            EditorCommands()
        }
    }
}

extension UTType {
    nonisolated static let overlayProject = UTType(
        exportedAs: ProjectPackage.contentTypeIdentifier, conformingTo: .package)
}

/// Menu commands that act on the focused editor.
struct EditorCommands: Commands {
    @FocusedValue(\.editor) private var editor

    var body: some Commands {
        CommandMenu("Project") {
            Button("Add Video…") { editor?.addVideo() }.keyboardShortcut("i", modifiers: [.command])
            Button("Add Data File…") { editor?.addData() }.keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            Menu("Add Display Object") {
                ForEach(DisplayObject.templates, id: \.name) { template in
                    Button(template.name) { editor?.addObject(template.kind) }
                }
                Divider()
                Button("Image…") { editor?.addImage() }
            }
            Button("Delete Selected Object") { editor?.deleteSelectedObject() }.keyboardShortcut(.delete, modifiers: [])
            Divider()
            Button("Copy Object Style") { editor?.copyStyle() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(editor?.selectedObject == nil)
            Button("Paste Object Style") { editor?.pasteStyle() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(editor?.canPasteStyle != true)
            Button("Import Object Style…") { editor?.importStyle() }
            Button("Export Object Style…") { editor?.exportStyle() }.disabled(editor?.selectedObject == nil)
            Divider()
            Menu("Camera Layout") {
                ForEach(LayoutPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) { editor?.applyLayout(preset) }
                }
            }
            Button("Add Segment at Playhead") { editor?.addSegmentAtPlayhead() }
                .keyboardShortcut("k", modifiers: [.command])
            Button("Delete Selected Segment") {
                if let id = editor?.selectedSegmentID { editor?.deleteSegment(id) }
            }
            .disabled(editor?.selectedSegmentID == nil)
            Divider()
            Button("Synchronize Data…") { editor?.showSyncWizard = true }.keyboardShortcut("y", modifiers: [.command])
            Button("Export Video…") { editor?.showExport = true }.keyboardShortcut("e", modifiers: [.command])
        }
        CommandMenu("Playback") {
            Button(editor?.isPlaying == true ? "Pause" : "Play") { editor?.togglePlayback() }.keyboardShortcut(
                .space, modifiers: [])
            Button("Step Back") { editor?.step(by: -1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Step Forward") { editor?.step(by: 1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Go to Start") { editor?.seek(to: 0) }.keyboardShortcut(.home, modifiers: [])
        }
    }
}

struct EditorFocusKey: FocusedValueKey {
    typealias Value = EditorModel
}

extension FocusedValues {
    var editor: EditorModel? {
        get { self[EditorFocusKey.self] }
        set { self[EditorFocusKey.self] = newValue }
    }
}
