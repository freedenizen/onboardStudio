import ProjectModel
import SwiftUI
import UniformTypeIdentifiers

struct EditorView: View {
    @State private var editor: EditorModel
    @Environment(\.undoManager) private var undoManager
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(Preferences.tourSeen.key) private var tourSeen = false
    @AppStorage(Preferences.attributeMappings.key) private var globalMappings = Preferences.attributeMappings.unset

    init(document: ProjectDocument, fileURL: URL?) {
        _editor = State(initialValue: EditorModel(document: document, fileURL: fileURL))
    }

    var body: some View {
        // A plain split view holds the inspector: SwiftUI's `.inspector` adds twice its ideal width to
        // the window's minimum, which kept the window from fitting 1024-point displays.
        HSplitView {
            NavigationSplitView {
                SidebarView(editor: editor)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240)
            } detail: {
                VStack(spacing: 0) {
                    if editor.pictureTool != nil {
                        PictureToolBar(editor: editor)
                        Divider()
                    }
                    PreviewView(editor: editor)
                    Divider()
                    // Under the preview, not over it: manual sync is judged by looking at the
                    // picture while nudging, which a sheet made impossible.
                    if editor.showSyncWizard {
                        SyncPanelView(editor: editor)
                        Divider()
                    }
                    TransportView(editor: editor)
                    TimelineView(editor: editor)
                    StatusLineView(editor: editor)
                }
            }
            .frame(minWidth: 700)
            .layoutPriority(1)
            if editor.showInspector {
                InspectorView(editor: editor)
                    .frame(minWidth: 280, idealWidth: 300, maxWidth: 460)
            }
        }
        .toolbar { EditorToolbar(editor: editor) }
        .overlay { TourOverlay(editor: editor) }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                var urls: [URL] = []
                for provider in providers {
                    if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                        urls.append(url)
                    } else if let data = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier)
                        as? Data,
                        let url = URL(dataRepresentation: data, relativeTo: nil)
                    {
                        urls.append(url)
                    }
                }
                editor.addDroppedFiles(urls.sorted { $0.lastPathComponent < $1.lastPathComponent })
            }
            return true
        }
        .focusedSceneValue(\.editor, editor)
        .sheet(isPresented: $editor.showExport) { ExportSheet(editor: editor) }
        .sheet(item: $editor.clipRequest) { request in VerticalClipSheet(editor: editor, request: request) }
        .sheet(isPresented: $editor.showSaveTemplate) { SaveTemplateSheet(editor: editor) }
        .sheet(isPresented: $editor.showCompareLaps) { CompareLapsSheet(editor: editor) }
        .sheet(item: $editor.uploadURL) { url in UploadSheet(file: url) }
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
            dismissWindow(id: "launcher")  // a project is open; the welcome window has done its job
            // The attribute window is its own scene, so `@FocusedValue` cannot reach this editor
            // from it; this is how it follows whichever project is in front.
            ActiveEditor.shared.editor = editor
            UITestSupport.editorAppeared(editor)
            if !tourSeen {
                tourSeen = true
                editor.tourStep = 0
            }
            if let template = PendingTemplate.shared.template, editor.project.displayObjects.isEmpty,
                editor.project.inputs.isEmpty
            {
                PendingTemplate.shared.template = nil
                editor.apply(template)
            }
            editor.scheduleCompile()
        }
        .onChange(of: undoManager) { _, newValue in editor.undoManager = newValue }
        // The mapping for all projects lives in preferences, not in this document, so no edit of
        // the project notices it change; without this an open project kept its old channels (#214).
        .onChange(of: globalMappings) { editor.scheduleCompile() }
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
            .help("Add a video, or every file of one recording (⌘I)")
            .accessibilityIdentifier("toolbar.addVideo")
            Button {
                editor.addData()
            } label: {
                Label("Add Data", systemImage: "doc.badge.plus")
            }
            .help("Add a data file from a logger or phone app (⇧⌘D)")
            .accessibilityIdentifier("toolbar.addData")
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
            .help("Add a gauge, map, timer, readout, text or image")
            // A toolbar menu is read by its symbol's name unless it is told otherwise (#153).
            .accessibilityLabel("Add Object")
            .accessibilityIdentifier("toolbar.addObject")
            Menu {
                ForEach(LayoutPreset.allCases, id: \.self) { preset in
                    Button(preset.displayName) { editor.applyLayout(preset) }
                }
                Divider()
                Button("Add Segment at Playhead") { editor.addSegmentAtPlayhead() }
            } label: {
                Label("Layout", systemImage: "rectangle.3.group")
            }
            .help("Arrange the cameras, or start a new segment at the playhead")
            .accessibilityLabel("Layout")
            .accessibilityIdentifier("toolbar.layout")
            .disabled(editor.project.videoInputs.isEmpty)
            Button {
                editor.showSyncWizard = true
            } label: {
                Label("Sync", systemImage: "arrow.left.arrow.right")
            }
            .help("Line the data up with the video (⌘Y)")
            .accessibilityIdentifier("toolbar.sync")
            .disabled(editor.project.dataInputs.isEmpty || editor.project.videoInputs.isEmpty)
            Button {
                editor.showExport = true
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .help("Export the finished video (⌘E)")
            .accessibilityIdentifier("toolbar.export")
            .disabled(editor.project.videoInputs.isEmpty || !editor.canExport)
        }
        // At the trailing end, over the inspector it shows and hides, as in Pages and Keynote (#280).
        ToolbarItem(placement: .primaryAction) {
            Button {
                editor.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.right")
            }
            .help(editor.showInspector ? "Hide the inspector (⌥⌘I)" : "Show the inspector (⌥⌘I)")
            .accessibilityLabel(editor.showInspector ? "Hide Inspector" : "Show Inspector")
            .accessibilityIdentifier("toolbar.inspector")
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// What the app last did on the user's behalf (chapters joined, sync applied, a file refused…).
/// Stays until replaced or dismissed; everything it has said is a click away (#112).
struct StatusLineView: View {
    @Bindable var editor: EditorModel

    var body: some View {
        if editor.statusMessage != nil || editor.showActivity {
            HStack(spacing: 8) {
                Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
                Text(editor.statusMessage ?? "").font(.callout).lineLimit(2).textSelection(.enabled)
                    .help(editor.statusMessage ?? "")
                    .accessibilityIdentifier("status.message")
                Spacer()
                Button {
                    editor.showActivity.toggle()
                } label: {
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Show everything the app has done in this project (⌥⌘L)")
                .accessibilityLabel("Show Activity")
                .accessibilityIdentifier("status.activity")
                .popover(isPresented: $editor.showActivity, arrowEdge: .top) { ActivityLogView(log: editor.activity) }
                Button {
                    editor.statusMessage = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain).help("Dismiss this message")
                .accessibilityLabel("Dismiss").accessibilityIdentifier("status.dismiss")
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.bar)
            .transition(.move(edge: .bottom))
        }
    }
}
