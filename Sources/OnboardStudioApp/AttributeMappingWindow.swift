import ProjectModel
import SwiftUI
import TelemetryKit

/// The attribute mapping table and the import report, in a window of their own (#192).
///
/// The table has three columns and an inspector can show one. Squeezed into a ~300 pt column each
/// row became three lines, which made a long scroll inside a longer one and got worse as the
/// vocabulary grew. Here the columns are columns, and the window can be left open beside the
/// editor while the preview is checked.
///
/// Laid out as a Mac utility is (#200): the level being edited is a sidebar, so the other levels
/// stay in view and the scope comes first in reading order; what is shown of it is the toolbar's
/// business, with a filter field beside it. The window remembers its scope, its view and its
/// toggles between launches.
struct AttributeMappingWindow: View {
    /// The scope as last chosen. Stored as text so the window can restore it; read through `scope`,
    /// which falls back when what was stored no longer exists.
    @SceneStorage("attributes.scope") private var storedScope = AttributeMappingScope.global.storageValue
    @SceneStorage("attributes.tab") private var storedTab: Tab = .attributes
    @SceneStorage("attributes.showAll") private var showEveryAttribute = false
    @SceneStorage("import.showAll") private var showEveryColumn = false
    @State private var filter = ""
    /// Counts Return presses in the filter, for the table to answer by focusing its first row.
    @State private var filterSubmits = 0
    @FocusState private var filterFocused: Bool
    @FocusState private var focus: AttributeFocus?

    private var active = ActiveEditor.shared
    private var router = AttributeWindowRouter.shared

    enum Tab: String, CaseIterable, Identifiable {
        case attributes, report
        var id: String { rawValue }
        var title: String { self == .attributes ? "Attributes" : "Import" }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 280)
        } detail: {
            content
                .frame(minWidth: 720, minHeight: 400)
                .toolbar {
                    if active.editor != nil {
                        ToolbarItem(placement: .principal) {
                            Picker("View", selection: tabSelection) {
                                ForEach(Tab.allCases) { Text($0.title).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .help("Show the attribute table, or what became of each column of the file")
                            .accessibilityIdentifier("attributes.tab")
                        }
                    }
                }
                .searchable(text: $filter, placement: .toolbar, prompt: filterPrompt)
                .searchFocused($filterFocused)
                // Return in the filter goes to the first row it left, so ⌘F, a word, Return and a
                // column name is the whole of mapping an attribute from the keyboard.
                .onSubmit(of: .search) { filterSubmits += 1 }
        }
        .focusedSceneValue(\.attributeTab, tabSelection)
        .focusedSceneValue(\.attributeShowAll, tab == .attributes ? $showEveryAttribute : $showEveryColumn)
        .focusedSceneValue(\.attributeFilterFocus, FocusFilterAction { filterFocused = true })
        .onAppear(perform: takeRequest)
        .onChange(of: router.request) { takeRequest() }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: scopeSelection) {
            Section("Applies to") {
                Label("All projects", systemImage: "globe")
                    .tag(AttributeMappingScope.global)
                    .help("The mapping every later import follows, kept in Settings")
                    .accessibilityIdentifier("attributes.scope.global")
                if active.editor != nil {
                    Label("This project", systemImage: "doc")
                        .tag(AttributeMappingScope.project)
                        .help("Where this project differs from all projects")
                        .accessibilityIdentifier("attributes.scope.project")
                }
            }
            if !dataInputs.isEmpty {
                Section("Data files") {
                    ForEach(dataInputs, id: \.id) { input in
                        Label(input.label, systemImage: "waveform.path.ecg")
                            .tag(AttributeMappingScope.input(input.id))
                            .help("Where this file differs from the project, when it is the exception")
                            .accessibilityIdentifier("attributes.scope.input.\(input.label)")
                    }
                }
            }
        }
        .accessibilityIdentifier("attributes.scope")
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch tab {
        case .report:
            if let session = selectedSession {
                ImportReportTable(report: session.importReport, filter: filter, showEverything: $showEveryColumn)
            } else {
                noDataFile(
                    "The import report says what became of each column of a data file. Add one to this "
                        + "project to see it.")
            }
        case .attributes:
            AttributeMappingGrid(
                scope: scope, editor: active.editor, filter: filter, filterSubmits: filterSubmits,
                showAll: $showEveryAttribute, focus: $focus)
        }
    }

    /// Says why there is nothing to show, and offers the way to fix it (#200).
    private func noDataFile(_ description: String) -> some View {
        ContentUnavailableView {
            Label("No data file", systemImage: "waveform.path.ecg")
        } description: {
            Text(description)
        } actions: {
            if let editor = active.editor {
                Button("Add Data File…") { editor.addData() }
                    .accessibilityIdentifier("attributes.addData")
            }
        }
    }

    // MARK: - State

    /// The scope in force: what was stored, unless it names something that is not there — an input
    /// of a project that closed, or a project when none is open.
    private var scope: AttributeMappingScope {
        let stored = AttributeMappingScope(storageValue: storedScope) ?? .global
        guard let editor = active.editor else { return .global }
        if let id = stored.inputID, !editor.project.dataInputs.contains(where: { $0.id == id }) {
            return .project
        }
        return stored
    }

    private var scopeSelection: Binding<AttributeMappingScope?> {
        Binding(get: { scope }, set: { if let new = $0 { storedScope = new.storageValue } })
    }

    /// The Import tab is about a data file, so without a project there is only the table.
    private var tab: Tab { active.editor == nil ? .attributes : storedTab }

    private var tabSelection: Binding<Tab> {
        Binding(get: { tab }, set: { storedTab = $0 })
    }

    private var filterPrompt: String { tab == .attributes ? "Filter attributes" : "Filter columns" }

    private var dataInputs: [Input] { active.editor?.project.dataInputs ?? [] }

    /// The session the report describes: the selected input's, or the first one when the scope is
    /// the project or the global mapping and there is nothing more specific to show.
    private var selectedSession: TelemetrySession? {
        guard let editor = active.editor else { return nil }
        if let id = scope.inputID { return editor.sessions[id] }
        return editor.project.dataInputs.first.flatMap { editor.sessions[$0.id] }
    }

    /// Applies what a menu command or an inspector button asked the window to show.
    private func takeRequest() {
        guard let request = router.request else { return }
        router.request = nil
        if let scope = request.scope { storedScope = scope.storageValue }
        storedTab = request.tab
    }
}

extension AttributeMappingWindow {
    static let windowID = "attributes"

    /// Opens the window on `scope` and `tab`. The scope is the selected data input's when there is
    /// one, because that is the file the user was looking at when they asked.
    static func open(
        _ openWindow: OpenWindowAction, scope: AttributeMappingScope? = nil, tab: Tab = .attributes
    ) {
        AttributeWindowRouter.shared.request = AttributeWindowRouter.Request(scope: scope, tab: tab)
        openWindow(id: windowID)
    }

    /// The scope to open on from an editor: its selected data input, or the project.
    static func scope(for editor: EditorModel?) -> AttributeMappingScope? {
        guard let editor else { return nil }
        if let input = editor.selectedInput, input.kind.isData { return .input(input.id) }
        return .project
    }
}

/// Which text field of the attribute table has keyboard focus, so the window can put it
/// somewhere useful: on the first row when it opens, and on the first match when Return is
/// pressed in the filter (#200).
enum AttributeFocus: Hashable {
    case source(String)
    case threshold(String)
}

/// What the attribute window was last asked to show, by a menu command or an inspector button.
///
/// The window is a single `Window` scene, so `openWindow` cannot carry a value to it; this is the
/// value, handed over the way `ActiveEditor` hands over the editor.
@MainActor @Observable final class AttributeWindowRouter {
    static let shared = AttributeWindowRouter()

    struct Request: Equatable {
        var scope: AttributeMappingScope?
        var tab: AttributeMappingWindow.Tab
        /// Two identical requests in a row are still two requests: the second must reapply what
        /// the user changed in between.
        let id = UUID()
    }

    var request: Request?

    private init() {}
}

/// A button that opens the window, for the places that used to hold the table itself.
struct OpenAttributeWindowButton: View {
    let title: String
    /// Distinct per place, because more than one of these can share an inspector and a query for
    /// "the button that opens the window" would then match several.
    let identifier: String
    let scope: AttributeMappingScope?
    let tab: AttributeMappingWindow.Tab
    @Environment(\.openWindow) private var openWindow

    init(
        _ title: String = "Map Attributes…", identifier: String = "attributes.open",
        scope: AttributeMappingScope? = nil, tab: AttributeMappingWindow.Tab = .attributes
    ) {
        self.title = title
        self.identifier = identifier
        self.scope = scope
        self.tab = tab
    }

    var body: some View {
        Button(title) { AttributeMappingWindow.open(openWindow, scope: scope, tab: tab) }
            .accessibilityIdentifier(identifier)
    }
}

/// Puts keyboard focus in the attribute window's filter field, for ⌘F.
struct FocusFilterAction {
    let perform: () -> Void
    func callAsFunction() { perform() }
}

extension FocusedValues {
    /// The attribute window's view, while it is the key window: for View ▸ Attributes (⌘1) and
    /// View ▸ Import Report (⌘2).
    @Entry var attributeTab: Binding<AttributeMappingWindow.Tab>?
    /// The attribute window's *Show every attribute* or *Show every column*, whichever its view has.
    @Entry var attributeShowAll: Binding<Bool>?
    /// Focuses the attribute window's filter field.
    @Entry var attributeFilterFocus: FocusFilterAction?
}
