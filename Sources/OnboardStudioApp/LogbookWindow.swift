import AppKit
import MediaKit
import ProjectModel
import SwiftUI
import TelemetryKit
import UniformTypeIdentifiers

/// The logbook as the app holds it, for the window (#347): read once, re-read after anything
/// that writes to it, so the table never shows a stale season.
@MainActor @Observable final class LogbookModel {
    static let shared = LogbookModel()

    private(set) var entries: [LogbookEntry] = []
    private(set) var cars: [Car] = []
    /// Sessions read in for coaching references (#352), by entry, kept for the app's life.
    private var sessions: [UUID: TelemetrySession] = [:]

    /// The entry's session, read once off the main thread.
    func session(for entry: LogbookEntry) async -> TelemetrySession? {
        if let cached = sessions[entry.id] { return cached }
        let loaded = await Task.detached(priority: .userInitiated) { LogbookReferences.load(entry) }.value
        if let loaded { sessions[entry.id] = loaded }
        return loaded
    }

    func reload() {
        let logbook = AppLogbook.shared
        entries = logbook.entries()
        cars = logbook.cars()
    }

    func remove(_ entry: LogbookEntry) {
        try? AppLogbook.shared.remove(id: entry.id)
        reload()
    }

    /// Writes an edited entry — its conditions and notes (#348) — and shows it.
    func save(_ entry: LogbookEntry) {
        try? AppLogbook.shared.save(entry)
        reload()
    }
}

/// Hands a session to the next editor that appears (Open as Project).
@MainActor
final class PendingLogbookOpen {
    static let shared = PendingLogbookOpen()
    var entry: LogbookEntry?
}

/// Every track day in one place (#347): a sidebar of circuits, cars and years, a sortable,
/// searchable table of sessions, and a detail pane with the laps and the way into a project.
struct LogbookWindow: View {
    static let windowID = "logbook"

    @SceneStorage("logbook.scope") private var storedScope = "all"
    /// Sessions, or the trends across visits (#353).
    @SceneStorage("logbook.view") private var view: LogbookView = .sessions

    enum LogbookView: String, CaseIterable, Identifiable {
        case sessions, trends
        var id: String { rawValue }
        var title: String { self == .sessions ? "Sessions" : "Trends" }
    }
    @State var scope: LogbookScope = .all
    @State private var search = ""
    @State private var selection: UUID?
    @State private var sortOrder = [KeyPathComparator(\LogbookEntry.date, order: .reverse)]
    @State private var trackDay: TrackDayRequest?
    @State private var confirmRemoval: LogbookEntry?
    /// What the last export or import did, under the table (#350).
    @State var message: String?
    @Environment(\.openWindow) private var openWindow
    var model = LogbookModel.shared
    private var active = ActiveEditor.shared

    static func open(_ openWindow: OpenWindowAction) { openWindow(id: windowID) }

    var body: some View {
        NavigationSplitView {
            sidebar.navigationSplitViewColumnWidth(min: 170, ideal: 200, max: 280)
        } detail: {
            content
                .frame(minWidth: 720, minHeight: 420)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Picker("View", selection: $view) {
                            ForEach(LogbookView.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("The sessions, or how the lap times and corners moved across visits to a circuit")
                        .accessibilityIdentifier("logbook.view")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Track Day…", systemImage: "plus") {
                            let urls = OpenPanels.chooseTrackDay()
                            if !urls.isEmpty { trackDay = TrackDayRequest(urls: urls) }
                        }
                        .help("Enter a day's telemetry files and camera clips in the logbook")
                        .accessibilityIdentifier("logbook.addTrackDay")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Export Logbook…") { exportLogbook(includingFiles: false) }
                            Button("Export Logbook with Data Files…") { exportLogbook(includingFiles: true) }
                            Divider()
                            Button("Export Sessions as CSV…") { exportCSV(laps: false) }
                            Button("Export Laps as CSV…") { exportCSV(laps: true) }
                            Button("Export as Markdown…") { exportMarkdown() }
                            Divider()
                            Button("Import Logbook…") { importLogbook() }
                        } label: {
                            Label("Export or Import", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel("Export or Import")
                        .help("Take the logbook with you as files, as CSV or Markdown, or read one in")
                        .accessibilityIdentifier("logbook.transfer")
                    }
                }
                .searchable(text: $search, placement: .toolbar, prompt: "Circuit, car, driver, notes")
        }
        .sheet(item: $trackDay) { request in
            TrackDayImportSheet(editor: active.editor, request: request).onDisappear { model.reload() }
        }
        .onAppear { model.reload() }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            Task { @MainActor in
                let urls = await Self.urls(from: providers)
                if !urls.isEmpty { trackDay = TrackDayRequest(urls: urls) }
            }
            return true
        }
        .confirmationDialog(
            "Remove this session from the logbook?",
            isPresented: Binding(get: { confirmRemoval != nil }, set: { if !$0 { confirmRemoval = nil } }),
            presenting: confirmRemoval
        ) { entry in
            Button("Remove from Logbook", role: .destructive) {
                model.remove(entry)
                if selection == entry.id { selection = nil }
            }
        } message: { entry in
            Text("\(entry.title) is taken out of the logbook. The file itself is not touched.")
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: Binding(get: { scope }, set: { if let new = $0 { scope = new } })) {
            Label("All Sessions", systemImage: "book.closed").tag(LogbookScope.all)
                .accessibilityIdentifier("logbook.scope.all")
            let circuits = LogbookFilter.circuits(in: model.entries)
            if !circuits.isEmpty {
                Section("Circuits") {
                    ForEach(circuits, id: \.scope) { group in
                        Label(group.scope.title, systemImage: "flag.checkered").badge(group.count).tag(group.scope)
                    }
                }
            }
            let cars = LogbookFilter.cars(in: model.entries)
            if !cars.isEmpty {
                Section("Cars") {
                    ForEach(cars, id: \.scope) { group in
                        Label(group.scope.title, systemImage: "car").badge(group.count).tag(group.scope)
                    }
                }
            }
            let years = LogbookFilter.years(in: model.entries)
            if !years.isEmpty {
                Section("Years") {
                    ForEach(years, id: \.scope) { group in
                        Label(group.scope.title, systemImage: "calendar").badge(group.count).tag(group.scope)
                    }
                }
            }
        }
        .accessibilityIdentifier("logbook.sidebar")
    }

    // MARK: - Table and detail

    var shown: [LogbookEntry] {
        LogbookFilter.apply(model.entries, scope: scope, search: search).sorted(using: sortOrder)
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty {
            ContentUnavailableView {
                Label("No Track Days Yet", systemImage: "book.closed")
            } description: {
                Text(
                    "The logbook keeps every session the app reads: where and when, the car, every lap. "
                        + "Add a day's files or folders to begin, or add a data file to a project.")
            } actions: {
                Button("Add Track Day…") {
                    let urls = OpenPanels.chooseTrackDay()
                    if !urls.isEmpty { trackDay = TrackDayRequest(urls: urls) }
                }
            }
        } else if view == .trends {
            LogbookTrendsView(
                entries: model.entries, circuitKey: trendsCircuit?.id, circuitTitle: trendsCircuit?.title ?? "",
                onOpen: { id in
                    selection = id
                    view = .sessions
                })
        } else {
            HSplitView {
                VStack(spacing: 0) {
                    LogbookTable(
                        entries: shown, bests: PersonalBests.entriesSettingBests(in: model.entries),
                        selection: $selection, sortOrder: $sortOrder)
                    if let message {
                        Divider()
                        Text(message).font(.callout).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                            .accessibilityIdentifier("logbook.message")
                    }
                }
                .frame(minWidth: 460)
                .layoutPriority(1)
                if let entry = model.entries.first(where: { $0.id == selection }) {
                    LogbookDetail(
                        entry: entry, hasProject: active.editor != nil,
                        openAsProject: { openAsProject(entry) },
                        addToProject: { addToCurrentProject(entry) },
                        remove: { confirmRemoval = entry },
                        save: { model.save($0) },
                        personalBest: PersonalBests.best(in: model.entries, circuitKey: circuitKey(of: entry)),
                        visits: PersonalBests.visits(in: model.entries, circuitKey: circuitKey(of: entry))
                    )
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 420)
                }
            }
        }
    }

    private func circuitKey(of entry: LogbookEntry) -> String { LogbookFilter.circuitKey(of: entry) }

    /// The circuit the trends are of: the one chosen in the sidebar, else the only one there is.
    private var trendsCircuit: (id: String, title: String)? {
        if case .circuit(let id, let title) = scope { return (id, title) }
        let circuits = LogbookFilter.circuits(in: model.entries)
        if circuits.count == 1, case .circuit(let id, let title) = circuits[0].scope { return (id, title) }
        return nil
    }

    // MARK: - Into a project

    func openAsProject(_ entry: LogbookEntry) {
        guard entry.resolveFile() != nil else { return }
        PendingLogbookOpen.shared.entry = entry
        NSDocumentController.shared.newDocument(nil)
    }

    func addToCurrentProject(_ entry: LogbookEntry) {
        guard let editor = active.editor, let url = entry.resolveFile() else { return }
        editor.addData(at: url)
        NSApp.activate()
    }

    static func urls(from providers: [NSItemProvider]) async -> [URL] {
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier("public.file-url") {
            if let item = try? await provider.loadItem(forTypeIdentifier: "public.file-url"),
                let data = item as? Data, let url = URL(dataRepresentation: data, relativeTo: nil)
            {
                urls.append(url)
            }
        }
        return urls
    }
}
