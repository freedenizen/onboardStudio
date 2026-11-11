import MediaKit
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
        // Under UI tests the compile reads the scratch logbook the tests fill, never the user's.
        ProjectCompiler.logbookDirectory = UITestSupport.logbookDirectory
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
                    let user = TemplateLibrary.app.entries()
                    if !user.isEmpty { Divider() }
                    ForEach(user) { entry in
                        Button(entry.name) {
                            if let template = try? TemplateLibrary.app.load(entry) { newDocument(from: template) }
                        }
                    }
                }
                // Adds a template someone shared to the welcome window and the menu above (#44).
                Button("Import Template…") { TemplateImport.chooseAndAdd() }
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            }
            // Declared first so the Session menu stands between View and Project (#450).
            LogbookCommands()
            EditorCommands()
            TimelineCommands()
            UndoCommands()
            SidebarCommands()
            ToolbarCommands()
            AttributeWindowCommands()
            CoachingSheetCommands()
            if UITestSupport.isActive { UITestCommands() }
        }
        // The template cards with their right-click management (#44), once the welcome window.
        Window("Templates", id: TemplatesWindow.windowID) {
            TemplatesWindow()
        }
        .defaultSize(width: 760, height: 440)
        Window("Attributes", id: AttributeMappingWindow.windowID) {
            AttributeMappingWindow()
        }
        .defaultSize(width: 900, height: 560)
        Window("Coaching", id: CoachingWindow.windowID) {
            CoachingWindow()
        }
        .defaultSize(width: 1000, height: 640)
        // Laps raced round the circuit in 3D (#415); ⌃⌘R, as Coaching is ⌃⌘C.
        Window("Replay", id: ReplayWindow.windowID) {
            ReplayWindow()
        }
        .defaultSize(width: 1100, height: 700)
        .keyboardShortcut("r", modifiers: [.command, .control])
        // A Window scene lists itself in the Window menu; ⌃⌘L opens it (#347), the pattern Show
        // Project Details (⌃⌘I) and Coaching (⌃⌘C) set for "show me a view".
        // And the window at launch (#395): where a track day begins, and every project after it.
        Window("Logbook", id: LogbookWindow.windowID) {
            LogbookWindow()
        }
        .defaultSize(width: 1000, height: 620)
        .keyboardShortcut("l", modifiers: [.command, .control])
        .defaultLaunchBehavior(LaunchOptions.openLogbook ? .presented : .suppressed)
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
///
/// With no project in front — the Logbook, Coaching without a project — every item that acts on a
/// project is dimmed, and gives up its key (#450): a dimmed item still takes its key and does
/// nothing with it, which would leave Space, Delete and ⌃⌘C dead in the window that is in front.
struct EditorCommands: Commands {
    @FocusedValue(\.editor) private var editor
    @Environment(\.openWindow) private var openWindow

    /// A project is in front: its items are live and hold their keys.
    private var live: Bool { editor != nil }

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Onboard Studio User Guide") { HelpLinks.open(.userGuide) }
            Button("Supported Data Formats") { HelpLinks.open(.formats) }
            Button("Scripting Reference") { HelpLinks.open(.scripting) }
            Button("YouTube Upload Setup") { HelpLinks.open(.youtube) }
            Button("Project File Format") { HelpLinks.open(.projectFormat) }
            Divider()
            Button("Keyboard Shortcuts") { openWindow(id: "shortcuts") }
            Button("Take the Tour") { editor?.tourStep = 0 }.disabled(editor == nil)
            Button("Show Getting Started") { UserDefaults.standard.set(true, for: Preferences.showGettingStarted) }
            Divider()
            Button("Open the Sample Project") { SampleProject.open() }.disabled(!SampleProject.isAvailable)
            Divider()
            // Everything a bug report needs, in one file the user sends themselves (#152).
            Button("Export Diagnostics…") { DiagnosticsExport.run(editor: editor) }
        }
        CommandGroup(after: .newItem) {
            // Where a track day begins (#393): the Logbook window, with the sheet up.
            Button("New Track Day…") {
                LogbookModel.shared.newDayRequested = true
                LogbookWindow.open(openWindow)
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
        }
        CommandGroup(after: .pasteboard) {
            // ⇧⌘A, as in Keynote, Pages and Freeform (#280).
            Button("Deselect All") { editor?.deselectAll() }
                .keyboardShortcut("a", modifiers: [.command, .shift], when: live)
                .disabled(editor?.hasSelection != true)
        }
        CommandMenu("Project") {
            Group {
                Button("Add Video…") { editor?.addVideo() }.keyboardShortcut("i", modifiers: [.command], when: live)
                Button("Add Camera…") { editor?.addCamera() }.keyboardShortcut(
                    "i", modifiers: [.command, .shift], when: live)
                Button("Add Data File…") { editor?.addData() }.keyboardShortcut(
                    "d", modifiers: [.command, .shift], when: live)
                Divider()
                // The project's own inspector is what shows with nothing selected, which nothing
                // else in the app says; this is the way to it from anywhere (#74, #118).
                Button("Show Project Details") { editor?.showProjectInspector() }
                    .keyboardShortcut("i", modifiers: [.command, .control], when: live)
                Divider()
                Menu("Add Display Object") {
                    ForEach(DisplayObject.templates, id: \.name) { template in
                        Button(template.name) { editor?.addObject(template.kind) }
                    }
                    Divider()
                    Button("Image…") { editor?.addImage() }
                }
                // A submenu's title is not dimmed by the group around it.
                .disabled(editor == nil)
                Button("Delete Selected Object") { editor?.deleteSelectedObject() }.keyboardShortcut(
                    .delete, modifiers: [], when: live
                )
                .disabled(editor?.pictureTool != nil)
                // Keynote's and Pages's keys for the same verbs (#90); ⌘G is Find Next elsewhere.
                Button("Group") { editor?.groupSelection() }
                    .keyboardShortcut("g", modifiers: [.command, .option], when: live)
                    .disabled(editor?.canGroupSelection != true)
                Button("Ungroup") { editor?.ungroupSelection() }
                    .keyboardShortcut("g", modifiers: [.command, .option, .shift], when: live)
                    .disabled(editor?.canUngroupSelection != true)
                Button(editor?.selectionIsLocked == true ? "Unlock" : "Lock") { editor?.toggleLockSelection() }
                    .keyboardShortcut("l", modifiers: [.command], when: live)
                    .disabled(editor?.selectedObjectID == nil)
                Divider()
                Button("Copy Object Style") { editor?.copyStyle() }
                    .keyboardShortcut("c", modifiers: [.command, .option], when: live)
                    .disabled(editor?.selectedObject == nil)
                Button("Paste Object Style") { editor?.pasteStyle() }
                    .keyboardShortcut("v", modifiers: [.command, .option], when: live)
                    .disabled(editor?.canPasteStyle != true)
                Button("Import Object Style…") { editor?.importStyle() }
                Button("Export Object Style…") { editor?.exportStyle() }.disabled(editor?.selectedObject == nil)
                Divider()
                Menu("Apply Template") {
                    ForEach(ProjectTemplate.builtIn, id: \.name) { template in
                        Button(template.name) { editor?.apply(template) }
                    }
                    let user = TemplateLibrary.app.entries()
                    if !user.isEmpty { Divider() }
                    ForEach(user) { entry in
                        Button(entry.name) { editor?.applyTemplate(at: entry.url) }
                    }
                    Divider()
                    Button("From File…") { editor?.importTemplate() }
                }
                // A submenu's title is not dimmed by the group around it.
                .disabled(editor == nil)
                Button("Save as Template…") { editor?.saveAsTemplate() }.disabled(editor == nil)
                Divider()
                Menu("Camera Layout") {
                    ForEach(LayoutPreset.allCases, id: \.self) { preset in
                        Button(preset.displayName) { editor?.applyLayout(preset) }
                    }
                }
                // A submenu's title is not dimmed by the group around it.
                .disabled(editor == nil)
                Button("Add Segment at Playhead") { editor?.addSegmentAtPlayhead() }
                    .keyboardShortcut("k", modifiers: [.command], when: live)
                // Resolve's ⇧[ / ⇧], verified in docs/conventions.md. Trimming to a marker is the
                // same command: ⇧↑/⇧↓ put the playhead on the marker first.
                // Resolve's Split Clip is ⌘\\ (manual p. 889/942).
                Button("Split at Playhead") { editor?.splitVideoAtPlayhead() }
                    .keyboardShortcut("\\", modifiers: [.command], when: live)
                    .disabled(editor?.canSplitAtPlayhead != true)
                Button("Trim Start to Playhead") { editor?.trimStartToPlayhead() }
                    .keyboardShortcut("[", modifiers: [.shift], when: live)
                    .disabled(editor?.canTrimToPlayhead != true)
                Button("Trim End to Playhead") { editor?.trimEndToPlayhead() }
                    .keyboardShortcut("]", modifiers: [.shift], when: live)
                    .disabled(editor?.canTrimToPlayhead != true)
                Button("Delete Selected Segment") {
                    if let id = editor?.selectedSegmentID { editor?.deleteSegment(id) }
                }
                .disabled(editor?.selectedSegmentID == nil)
                Divider()
                Button("Synchronize Data…") { editor?.showSyncWizard = true }.keyboardShortcut(
                    "y", modifiers: [.command], when: live)
            }
            .disabled(editor == nil)
            // ⌥⌘A: ⌘A and ⇧⌘A are Select All and Deselect All everywhere; with ⌥ it is free here
            // and in the Finder's sense unrelated. Opens on the selected data file (#200).
            Button("Map Attributes…") {
                AttributeMappingWindow.open(openWindow, scope: AttributeMappingWindow.scope(for: editor))
            }
            .keyboardShortcut("a", modifiers: [.command, .option])
            Group {
                Button("Show Import Report…") {
                    AttributeMappingWindow.open(
                        openWindow, scope: AttributeMappingWindow.scope(for: editor), tab: .report)
                }
                .disabled(editor?.project.dataInputs.isEmpty != false)
                Button("Export Video…") { editor?.showExport = true }.keyboardShortcut(
                    "e", modifiers: [.command], when: live
                )
                .disabled(editor?.canExport == false)
                // One lap, laid out for a phone, in one step (#151).
                Button("Export Lap as Vertical Clip…") { editor?.requestLapClip() }
                    .keyboardShortcut("e", modifiers: [.command, .shift], when: live)
                    .disabled(
                        editor?.project.videoInputs.isEmpty != false || editor?.project.dataInputs.isEmpty != false
                            || editor?.canExport == false)
                // The session's debrief as one video: cards and the corners that cost the most (#327).
                Button("Export Coaching Debrief…") { editor?.showDebrief = true }
                    .disabled(
                        editor?.project.videoInputs.isEmpty != false || editor?.project.dataInputs.isEmpty != false
                            || editor?.canExport == false)
                Divider()
                // Two laps side by side, kept level by distance (#154).
                Button("Compare Laps…") { editor?.showCompareLaps = true }
                    .disabled(
                        editor?.project.videoInputs.isEmpty != false || editor?.project.dataInputs.isEmpty != false)
                Button("Stop Comparing Laps") { editor?.stopComparingLaps() }
                    .disabled(editor?.project.lapComparison == nil)
                // ⌃⌘C: where the time went, in a window beside the document (#321). ⌘C copies, ⌥⌘C
                // copies an object's style; ⌃⌘ is the pattern Show Project Details (⌃⌘I) set.
                Button("Coaching…") { CoachingWindow.open(openWindow) }
                    .keyboardShortcut("c", modifiers: [.command, .control], when: live)
                Divider()
                Button("Upload Video to YouTube…") {
                    if let url = OpenPanels.chooseVideo() { editor?.uploadURL = url }
                }
            }
            .disabled(editor == nil)
        }
        CommandGroup(after: .toolbar) {
            Group {
                // Pages and Keynote put their inspector toggle here, with ⌥⌘I (#280).
                Button(editor?.showInspector == false ? "Show Inspector" : "Hide Inspector") {
                    editor?.showInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.command, .option], when: live)
                .disabled(editor == nil)
                Divider()
                // ⇧C and ⇧T, as Final Cut Pro's Crop and Transform (#275, #276).
                Button("Crop Picture") { editor?.beginCropping() }
                    .keyboardShortcut("c", modifiers: [.shift], when: live)
                    .disabled(editor?.canCropPicture != true)
                Button("Frame Picture") { editor?.beginFraming() }
                    .keyboardShortcut("t", modifiers: [.shift], when: live)
                    .disabled(editor?.canFramePicture != true)
                Divider()
                Button("Zoom In Timeline") { editor?.zoomTimeline(by: 1.5) }.keyboardShortcut(
                    "=", modifiers: [.command], when: live)
                Button("Zoom Out Timeline") { editor?.zoomTimeline(by: 1 / 1.5) }.keyboardShortcut(
                    "-", modifiers: [.command], when: live)
                Button("Zoom to Fit") { editor?.fitTimeline() }.keyboardShortcut("z", modifiers: [.shift], when: live)
                Toggle(
                    "Snapping",
                    isOn: Binding(get: { editor?.snappingEnabled ?? true }, set: { editor?.snappingEnabled = $0 }))
                Divider()
                // What the status line has said, all of it (#112).
                Button("Show Activity") { editor?.showActivity = true }
                    .keyboardShortcut("l", modifiers: [.command, .option], when: live)
                    .disabled(editor == nil)
            }
            .disabled(editor == nil)
        }
        // Keynote's Arrange menu and its keys (#277): ⇧⌘F and ⇧⌘B to the front and back, with ⌥
        // one step at a time.
        CommandMenu("Arrange") {
            ForEach(LayerMove.allCases, id: \.self) { move in
                Button(move.title) { editor?.arrangeSelection(move) }
                    .keyboardShortcut(
                        move == .forward || move == .toFront ? "f" : "b",
                        modifiers: move == .toFront || move == .toBack
                            ? [.command, .shift] : [.command, .shift, .option], when: live
                    )
                    .disabled(editor?.canArrangeSelection(move) != true)
            }
        }
    }
}

/// View-menu commands for the attribute window, present while it is the key window (#200).
///
/// ⌘1 and ⌘2 switch between its two views the way the Finder's ⌘1–⌘4 switch between its, and ⌘F
/// goes to its filter field. Outside the window the items are not there at all, so the keys do
/// nothing in the editor rather than something unexpected.
struct AttributeWindowCommands: Commands {
    @FocusedValue(\.attributeTab) private var tab
    @FocusedValue(\.attributeShowAll) private var showAll
    @FocusedValue(\.attributeFilterFocus) private var focusFilter

    var body: some Commands {
        CommandGroup(before: .toolbar) {
            if let tab {
                Toggle("Attributes", isOn: tab.selecting(.attributes)).keyboardShortcut("1", modifiers: .command)
                Toggle("Import Report", isOn: tab.selecting(.report)).keyboardShortcut("2", modifiers: .command)
                if let showAll {
                    Toggle(
                        tab.wrappedValue == .attributes ? "Show Every Attribute" : "Show Every Column", isOn: showAll)
                }
                Divider()
            }
        }
        CommandGroup(after: .textEditing) {
            if let focusFilter {
                Button(tab?.wrappedValue == .report ? "Filter Columns" : "Filter Attributes") { focusFilter() }
                    .keyboardShortcut("f", modifiers: .command)
            }
        }
    }
}

extension Binding where Value: Equatable {
    /// A menu checkmark for one view: on when it is the one showing, and choosing it shows it.
    func selecting(_ choice: Value) -> Binding<Bool> {
        Binding<Bool>(get: { wrappedValue == choice }, set: { if $0 { wrappedValue = choice } })
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
