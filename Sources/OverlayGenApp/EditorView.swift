import ProjectModel
import SwiftUI

struct EditorView: View {
    @State private var editor: EditorModel
    @Environment(\.undoManager) private var undoManager

    init(document: ProjectDocument, fileURL: URL?) {
        _editor = State(initialValue: EditorModel(document: document, fileURL: fileURL))
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(editor: editor)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            VStack(spacing: 0) {
                PreviewView(editor: editor)
                Divider()
                TransportView(editor: editor)
                TimelineView(editor: editor)
            }
        }
        .inspector(isPresented: .constant(true)) {
            InspectorView(editor: editor)
                .inspectorColumnWidth(min: 260, ideal: 300)
        }
        .toolbar { EditorToolbar(editor: editor) }
        .focusedSceneValue(\.editor, editor)
        .sheet(isPresented: $editor.showSyncWizard) { SyncWizardView(editor: editor) }
        .sheet(isPresented: $editor.showExport) { ExportSheet(editor: editor) }
        .alert(
            "Problem",
            isPresented: Binding(get: { editor.errorMessage != nil }, set: { if !$0 { editor.errorMessage = nil } })
        ) {
            Button("OK") { editor.errorMessage = nil }
        } message: {
            Text(editor.errorMessage ?? "")
        }
        .onAppear {
            editor.undoManager = undoManager
            editor.scheduleCompile()
        }
        .onChange(of: undoManager) { _, newValue in editor.undoManager = newValue }
    }
}

struct EditorToolbar: ToolbarContent {
    let editor: EditorModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                editor.addVideo()
            } label: {
                Label("Add Video", systemImage: "video.badge.plus")
            }
            Button {
                editor.addData()
            } label: {
                Label("Add Data", systemImage: "doc.badge.plus")
            }
            Menu {
                ForEach(DisplayObject.templates, id: \.name) { template in
                    Button(template.name) { editor.addObject(template.kind) }
                        .disabled(template.kind.needsData && editor.project.dataInputs.isEmpty)
                }
                Divider()
                Button("Image…") { editor.addImage() }
            } label: {
                Label("Add Object", systemImage: "gauge.with.dots.needle.33percent")
            }
            Menu {
                ForEach(LayoutPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) { editor.applyLayout(preset) }
                }
                Divider()
                Button("Add Segment at Playhead") { editor.addSegmentAtPlayhead() }
            } label: {
                Label("Layout", systemImage: "rectangle.3.group")
            }
            .disabled(editor.project.videoInputs.isEmpty)
            Button {
                editor.showSyncWizard = true
            } label: {
                Label("Sync", systemImage: "arrow.left.arrow.right")
            }
            .disabled(editor.project.dataInputs.isEmpty || editor.project.videoInputs.isEmpty)
            Button {
                editor.showExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(editor.project.videoInputs.isEmpty)
        }
    }
}
