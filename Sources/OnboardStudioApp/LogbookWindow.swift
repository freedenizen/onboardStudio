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
    /// The track days (#392), newest first; every entry is on one once `reload` has run.
    private(set) var days: [TrackDay] = []
    private(set) var cars: [Car] = []
    /// Sessions read in for coaching references (#352), by entry, kept for the app's life.
    private var sessions: [UUID: TelemetrySession] = [:]
    /// Files on their way into the logbook, shown by the window's sheet (#393).
    var trackDayRequest: TrackDayRequest?
    /// File ▸ New Track Day… asked for the sheet (#393).
    var newDayRequested = false
    /// The day chosen in the sidebar, for the Testing menu and the ways in.
    var selectedDay: TrackDay?

    private var carComparisons: [String: CarVersusCar] = [:]

    /// Two cars' best laps compared (#354), read once per pair of sessions.
    func carComparison(first: LogbookEntry, firstCar: String, second: LogbookEntry, secondCar: String) async
        -> CarVersusCar?
    {
        let key = "\(first.id)|\(second.id)"
        if let cached = carComparisons[key] { return cached }
        let made = await Task.detached(priority: .userInitiated) {
            CarVersusCar.make(first: first, firstCar: firstCar, second: second, secondCar: secondCar)
        }.value
        if let made { carComparisons[key] = made }
        return made
    }

    /// The entry's session, read once off the main thread.
    func session(for entry: LogbookEntry) async -> TelemetrySession? {
        if let cached = sessions[entry.id] { return cached }
        let loaded = await Task.detached(priority: .userInitiated) { LogbookReferences.load(entry) }.value
        if let loaded { sessions[entry.id] = loaded }
        return loaded
    }

    func reload() {
        let logbook = AppLogbook.shared
        // Entries from before days existed are put on one, by their date and circuit.
        try? logbook.ensureDays()
        entries = logbook.entries()
        days = logbook.days()
        cars = logbook.cars()
    }

    /// Writes an edited day — its car, driver, conditions, notes, clips — and shows it.
    func saveDay(_ day: TrackDay) {
        try? AppLogbook.shared.saveDay(day)
        reload()
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

    // MARK: - Into a project

    /// A new project with the session's data file, its clips and `template` (#394), showing
    /// `then` once it is open (#396).
    func openAsProject(_ entry: LogbookEntry, template: ProjectTemplate?, then: LogbookOpenRequest.Then? = nil) {
        guard entry.resolveFile() != nil else { return }
        PendingLogbookOpen.shared.request = LogbookOpenRequest(
            entry: entry, clips: clipURLs(of: entry), template: template, then: then)
        NSDocumentController.shared.newDocument(nil)
    }

    /// The clips of the session's day that are its picture, in the order they were recorded.
    func clips(of entry: LogbookEntry) -> [ClipRecord] {
        let clips = days.first { $0.id == entry.trackDayID }?.clips.filter { $0.sessionID == entry.id } ?? []
        return clips.sorted { ($0.recordedAt ?? .distantPast, $0.path) < ($1.recordedAt ?? .distantPast, $1.path) }
    }

    /// Each clip's files that still exist, chapters after their first.
    func clipURLs(of entry: LogbookEntry) -> [URL] {
        clips(of: entry).flatMap { clip -> [URL] in
            guard let first = clip.resolveFile() else { return [] }
            return [first]
                + clip.chapterPaths.map { URL(fileURLWithPath: $0) }.filter {
                    FileManager.default.fileExists(atPath: $0.path)
                }
        }
    }

    /// The built-in templates and the user's own, as New Project from Template offers them.
    static func templates() -> [ProjectTemplate] {
        ProjectTemplate.builtIn + TemplateLibrary.app.entries().compactMap { try? TemplateLibrary.app.load($0) }
    }

    /// The template the last New Project used (Classic Dash to begin with), `nil` for blank.
    static func lastTemplate() -> ProjectTemplate? {
        let name = UserDefaults.standard.string(forKey: "logbook.projectTemplate") ?? "Classic Dash"
        return templates().first { $0.name == name }
    }
}

/// What a new project is made of from the logbook (#394): the session's data file, the clips
/// that are its picture, a template to lay it out, and what to show once it is open.
struct LogbookOpenRequest {
    enum Then { case coaching, debrief }
    let entry: LogbookEntry
    var clips: [URL] = []
    var template: ProjectTemplate?
    var then: Then?
}

/// Hands a session to the next editor that appears (New Project).
@MainActor
final class PendingLogbookOpen {
    static let shared = PendingLogbookOpen()
    var request: LogbookOpenRequest?
}

/// Every track day in one place (#347): a sidebar of circuits, cars and years, a sortable,
/// searchable table of sessions, and a detail pane with the laps and the way into a project.
struct LogbookWindow: View {
    static let windowID = "logbook"

    @SceneStorage("logbook.scope") private var storedScope = "all"
    /// Sessions, or the trends across visits (#353).
    @SceneStorage("logbook.view") var view: LogbookView = .sessions

    enum LogbookView: String, CaseIterable, Identifiable {
        case sessions, trends, season
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sessions: "Sessions"
            case .trends: "Trends"
            case .season: "Season"
            }
        }
    }
    @State var scope: LogbookScope = .all
    @State private var search = ""
    @State private var selection: UUID?
    @State private var sortOrder = [KeyPathComparator(\LogbookEntry.date, order: .reverse)]
    @State private var confirmRemoval: LogbookEntry?
    @State private var confirmDayRemoval: TrackDay?
    /// What the last export or import did, under the table (#350).
    @State var message: String?
    @Environment(\.openWindow) var openWindow
    @Bindable var model = LogbookModel.shared
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
                        .help(
                            "The sessions; how the lap times and corners moved across visits to a circuit; "
                                + "or a year on one page"
                        )
                        .accessibilityIdentifier("logbook.view")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        newProjectMenu
                            .help("A blank project; the menu offers the templates, an existing project and the sample")
                            .accessibilityLabel("New Project")
                            .accessibilityIdentifier("logbook.newProject")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("New Track Day…", systemImage: "calendar.badge.plus") {
                            model.newDayRequested = true
                        }
                        .help("Begin a day: the date, the circuit, the car — before any file exists (⌥⌘N)")
                        .accessibilityIdentifier("logbook.newTrackDay")
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button("Add Files…", systemImage: "doc.badge.plus", action: addFiles)
                            .help(
                                "Enter a day's telemetry files and camera clips: on the day chosen in the sidebar, "
                                    + "else each on the day its date and circuit say"
                            )
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
        .sheet(item: $model.trackDayRequest) { request in
            TrackDayImportSheet(editor: active.editor, request: request).onDisappear { model.reload() }
        }
        .sheet(isPresented: $model.newDayRequested) {
            NewTrackDaySheet(
                knownCars: LogbookFilter.cars(in: model.entries).map(\.scope.title).filter { $0 != "No car" },
                lastDay: model.days.first, create: create)
        }
        .onAppear { model.reload() }
        .onChange(of: scope, initial: true) { model.selectedDay = selectedDay }
        .onChange(of: model.days) { model.selectedDay = selectedDay }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            let day = selectedDay
            Task { @MainActor in
                let urls = await Self.urls(from: providers)
                if !urls.isEmpty { model.trackDayRequest = TrackDayRequest(urls: urls, day: day) }
            }
            return true
        }
        .confirmationDialog(
            "Remove this track day from the logbook?",
            isPresented: Binding(get: { confirmDayRemoval != nil }, set: { if !$0 { confirmDayRemoval = nil } }),
            presenting: confirmDayRemoval
        ) { day in
            Button("Remove Track Day", role: .destructive) {
                try? AppLogbook.shared.removeDay(id: day.id, andSessions: true)
                model.reload()
                if case .day(let id, _) = scope, id == day.id { scope = .all }
            }
        } message: { day in
            let count = model.entries.filter { $0.trackDayID == day.id }.count
            Text(
                "\(day.label) and its \(count) session\(count == 1 ? "" : "s") are taken out of the logbook. "
                    + "The files are not touched.")
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

    // MARK: - Table and detail

    var shown: [LogbookEntry] {
        LogbookFilter.apply(model.entries, scope: scope, search: search).sorted(using: sortOrder)
    }

    @ViewBuilder private var content: some View {
        if model.entries.isEmpty, model.days.isEmpty {
            ContentUnavailableView {
                Label("No Track Days Yet", systemImage: "book.closed")
            } description: {
                Text(
                    "The logbook keeps every track day: where and when, the car, every session and its laps. "
                        + "Begin a day, or add a day's files or folders.")
            } actions: {
                Button("New Track Day…") { model.newDayRequested = true }
                    .accessibilityIdentifier("logbook.empty.newTrackDay")
                Button("Add Files…", action: addFiles)
                Button("New Project") { NSDocumentController.shared.newDocument(nil) }
            }
        } else if view == .season {
            SeasonView(
                entries: model.entries, plans: (active.editor?.trackLibrary ?? TrackLibrary()).all(),
                onOpen: { id in
                    selection = id
                    view = .sessions
                })
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
                    if let day = selectedDay {
                        TrackDayHeader(
                            day: day, sessions: model.entries.filter { $0.trackDayID == day.id },
                            save: { model.saveDay($0) }, addSessions: addFiles, remove: { confirmDayRemoval = day })
                        Divider()
                    }
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
                        entry: entry, clips: model.clips(of: entry), hasProject: active.editor != nil,
                        templates: LogbookModel.templates, newProject: { openAsProject(entry, template: $0) },
                        coach: { CoachingWindow.open(openWindow, entry: entry) },
                        compare: { compare(entry, with: $0) }, comparisons: comparisons(for: entry),
                        debrief: {
                            model.openAsProject(entry, template: ProjectTemplate.coachingDebrief, then: .debrief)
                        },
                        replay: { ReplayWindow.open(openWindow, entry: entry) },
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
        if let day = selectedDay, let id = day.circuitID { return (id, day.title) }
        let circuits = LogbookFilter.circuits(in: model.entries)
        if circuits.count == 1, case .circuit(let id, let title) = circuits[0].scope { return (id, title) }
        return nil
    }

    // MARK: - Into a project

    /// A new project with the session's data file, its clips and `template` (#394).
    func openAsProject(_ entry: LogbookEntry, template: ProjectTemplate?) {
        model.openAsProject(entry, template: template)
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
