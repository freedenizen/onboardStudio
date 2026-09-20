import ProjectModel
import SwiftUI
import UniformTypeIdentifiers

@main
struct OnboardStudioApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var updater = UpdaterModel()
    @State private var youtube = YouTubeModel()

    init() {
        LegacyMigration.run()
        LaunchOptions.registerDefaults()
    }

    var body: some Scene {
        DocumentGroup(
            newDocument: { ProjectDocument() },
            editor: { file in
                EditorView(document: file.document, fileURL: file.fileURL)
                    .environment(updater)
                    .environment(youtube)
            }
        )
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { NSDocumentController.shared.newDocument(nil) }.keyboardShortcut(
                    "n", modifiers: [.command])
                Menu("New from Template") {
                    ForEach(ProjectTemplate.builtIn, id: \.name) { template in
                        Button(template.name) { newDocument(from: template) }
                    }
                    let user = TemplateStore.userTemplates()
                    if !user.isEmpty { Divider() }
                    ForEach(user) { entry in
                        Button(entry.name) {
                            if let template = try? TemplateStore.load(entry.url) { newDocument(from: template) }
                        }
                    }
                }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            EditorCommands()
            if UITestSupport.isActive { UITestCommands() }
        }
        Window("Welcome to Onboard Studio", id: "launcher") {
            LauncherView()
        }
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .defaultLaunchBehavior(LaunchOptions.showLauncher ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        Window("Keyboard Shortcuts", id: "shortcuts") {
            ShortcutsView()
        }
        .windowResizability(.contentSize)
        Settings {
            SettingsView().environment(updater).environment(youtube)
        }
    }

    /// Opens a new untitled document showing the template's objects.
    func newDocument(from template: ProjectTemplate) {
        // The new window's editor picks the pending template up when it appears, which can happen
        // inside newDocument, so hand it over first.
        PendingTemplate.shared.template = template
        NSDocumentController.shared.newDocument(nil)
    }
}

/// Hands a template to the next editor that appears (New from Template).
@MainActor
final class PendingTemplate {
    static let shared = PendingTemplate()
    var template: ProjectTemplate?
}

extension UTType {
    nonisolated static let onboardProject = UTType(
        exportedAs: ProjectPackage.contentTypeIdentifier, conformingTo: .package)
    /// Projects saved under the app's former name, OverlayGen. Opened, never written.
    nonisolated static let legacyOverlayProject = UTType(
        importedAs: ProjectPackage.legacyContentTypeIdentifier, conformingTo: .package)
}

/// Menu commands that act on the focused editor.
struct EditorCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Onboard Studio User Guide") { HelpLinks.open(.userGuide) }
            Button("Supported Data Formats") { HelpLinks.open(.formats) }
            Button("Scripting Reference") { HelpLinks.open(.scripting) }
            Button("YouTube Upload Setup") { HelpLinks.open(.youtube) }
            Button("Project File Format") { HelpLinks.open(.projectFormat) }
            Divider()
            Button("Welcome to Onboard Studio") { openWindow(id: "launcher") }
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
            Button("Take the Tour") { editor?.tourStep = 0 }.disabled(editor == nil)
            Button("Show Getting Started") { UserDefaults.standard.set(true, forKey: "showGettingStarted") }
            Divider()
            Button("Open the Sample Project") { SampleProject.open() }.disabled(!SampleProject.isAvailable)
        }
        CommandMenu("Project") {
            Button("Add Video…") { editor?.addVideo() }.keyboardShortcut("i", modifiers: [.command])
            Button("Add Camera…") { editor?.addCamera() }.keyboardShortcut("i", modifiers: [.command, .shift])
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
            Menu("Apply Template") {
                ForEach(ProjectTemplate.builtIn, id: \.name) { template in
                    Button(template.name) { editor?.apply(template) }
                }
                let user = TemplateStore.userTemplates()
                if !user.isEmpty { Divider() }
                ForEach(user) { entry in
                    Button(entry.name) { editor?.applyTemplate(at: entry.url) }
                }
                Divider()
                Button("Import Template File…") { editor?.importTemplate() }
            }
            Button("Save as Template…") { editor?.saveAsTemplate() }
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
            Button("Upload Video to YouTube…") {
                if let url = OpenPanels.chooseVideo() { editor?.uploadURL = url }
            }
        }
        CommandGroup(after: .toolbar) {
            Divider()
            Button("Zoom In Timeline") { editor?.zoomTimeline(by: 1.5) }.keyboardShortcut("=", modifiers: [.command])
            Button("Zoom Out Timeline") { editor?.zoomTimeline(by: 1 / 1.5) }.keyboardShortcut(
                "-", modifiers: [.command])
            Button("Zoom to Fit") { editor?.fitTimeline() }.keyboardShortcut("z", modifiers: [.shift])
            Toggle(
                "Snapping",
                isOn: Binding(get: { editor?.snappingEnabled ?? true }, set: { editor?.snappingEnabled = $0 }))
        }
        CommandMenu("Marker") {
            // M to drop one, ⌘M to drop and name it, ⇧↑/⇧↓ to walk them: the Resolve bindings
            // recorded in docs/conventions.md, which Premiere shares.
            Button("Add Marker") { editor?.addMarkerAtPlayhead() }
                .keyboardShortcut("m", modifiers: [])
            Button("Add and Name Marker…") { editor?.addAndNameMarker() }
                .keyboardShortcut("m", modifiers: [.command])
            Button("Rename Marker…") { editor?.renameSelectedMarker() }
                .disabled(editor?.selectedMarkerID == nil)
            Button("Delete Marker") { editor?.deleteSelectedMarker() }
                .disabled(editor?.selectedMarkerID == nil)
            Divider()
            Button("Previous Marker") { editor?.goToPreviousMarker() }
                .keyboardShortcut(.upArrow, modifiers: [.shift])
            Button("Next Marker") { editor?.goToNextMarker() }
                .keyboardShortcut(.downArrow, modifiers: [.shift])
        }
        CommandMenu("Playback") {
            Button(editor?.isPlaying == true ? "Pause" : "Play") { editor?.togglePlayback() }.keyboardShortcut(
                .space, modifiers: [])
            // `,`/`.` rather than the arrows, which belong to the selected object: a menu key
            // equivalent is matched before the key reaches the picture, so binding the arrows
            // here would stop them ever nudging. See docs/conventions.md.
            Button("Step Back") { editor?.step(by: -1) }.keyboardShortcut(",", modifiers: [])
            Button("Step Forward") { editor?.step(by: 1) }.keyboardShortcut(".", modifiers: [])
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
